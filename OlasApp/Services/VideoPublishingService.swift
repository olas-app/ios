import AVFoundation
import CommonCrypto
import Foundation
import NDKSwiftCore
import SwiftUI
import UnifiedBlurHash

enum VideoPublishingError: LocalizedError {
    case noUploadServer
    case thumbnailGenerationFailed
    case uploadFailed
    case invalidUploadResponse
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .noUploadServer:
            return "No upload server configured. Please add a Blossom server in settings."
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        case .uploadFailed:
            return "Failed to upload video"
        case .invalidUploadResponse:
            return "Invalid response from upload server"
        case .fileNotFound:
            return "Video file not found"
        }
    }
}

/// Service for publishing videos to Nostr
struct VideoPublishingService {
    static func publish(
        ndk: NDK,
        videoURL: URL,
        caption: String,
        videoMode: VideoMode,
        onProgress: @MainActor (String, Double) -> Void
    ) async throws -> String {
        let serverURL: URL
        do {
            serverURL = try BlossomServerResolver.effectiveServerURL(ndk: ndk)
        } catch is BlossomServerError {
            throw VideoPublishingError.noUploadServer
        }

        // 1. Get video metadata
        await onProgress("Analyzing video...", 0.05)
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        // Get video dimensions
        var dimensions = "1280x720" // Default
        if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
            let size = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let videoSize = size.applying(transform)
            dimensions = "\(Int(abs(videoSize.width)))x\(Int(abs(videoSize.height)))"
        }

        // 2. Generate thumbnail
        await onProgress("Generating thumbnail...", 0.10)
        let thumbnailImage = try await generateThumbnail(from: videoURL)
        let blurhash = await UnifiedBlurHash.getBlurHashString(from: thumbnailImage)

        // 3. Compress/prepare thumbnail for upload
        guard let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.8) else {
            throw VideoPublishingError.thumbnailGenerationFailed
        }

        // 4. Upload thumbnail
        await onProgress("Uploading thumbnail...", 0.20)
        let client = BlossomClient()

        let thumbnailBlob = try await client.upload(
            data: thumbnailData,
            mimeType: "image/jpeg",
            to: serverURL.absoluteString,
            ndk: ndk,
            configuration: .default
        )

        // 5. Upload video using streaming (file-based) to avoid loading entire video into memory
        await onProgress("Uploading video...", 0.30)
        let videoBlob = try await uploadVideoFromFile(
            fileURL: videoURL,
            mimeType: "video/mp4",
            to: serverURL,
            ndk: ndk
        )

        await onProgress("Publishing...", 0.85)

        // 6. Publish event
        let kind: Kind = videoMode == .vine
            ? OlasConstants.EventKinds.divineVideo
            : OlasConstants.EventKinds.shortVideo

        let finalDimensions = dimensions
        let (event, _) = try await ndk.publish { builder in
            builder
                .kind(kind)
                .content(caption)
                // Video imeta tag
                .imetaTag(url: videoBlob.url) { imeta in
                    imeta.dim = finalDimensions
                    imeta.m = "video/mp4"
                    imeta.blurhash = blurhash
                }
                // Thumbnail as separate imeta
                .tag(["thumb", thumbnailBlob.url])
                // Duration in seconds
                .tag(["duration", String(Int(durationSeconds))])
                // Add title if caption is short enough
                .tag(["title", String(caption.prefix(50))])
        }

        await onProgress("Done!", 1.0)
        return event.id
    }

    // MARK: - Private Helpers

    private static func generateThumbnail(from videoURL: URL) async throws -> UIImage {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 720, height: 1280)

        // Get thumbnail from first frame
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)

        do {
            let cgImage = try await imageGenerator.image(at: time).image
            return UIImage(cgImage: cgImage)
        } catch {
            throw VideoPublishingError.thumbnailGenerationFailed
        }
    }

    // MARK: - Streaming File Upload

    /// Uploads a video file using streaming to avoid loading the entire file into memory.
    /// Uses URLSession.uploadTask(with:fromFile:) which streams directly from disk.
    private static func uploadVideoFromFile(
        fileURL: URL,
        mimeType: String,
        to serverURL: URL,
        ndk: NDK
    ) async throws -> BlossomBlob {
        let signer = try ndk.requireSigner()

        // Get file attributes without loading the file
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw VideoPublishingError.fileNotFound
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = attributes[.size] as? Int64 else {
            throw VideoPublishingError.uploadFailed
        }

        // Compute SHA256 using chunked reading on background thread (memory-efficient, non-blocking)
        // Use cancellation handler to propagate cancellation to the detached task
        let hashTask = Task.detached(priority: .utility) {
            try computeSHA256(of: fileURL)
        }
        let sha256Hex = try await withTaskCancellationHandler {
            try await hashTask.value
        } onCancel: {
            hashTask.cancel()
        }

        // Create Blossom auth event
        let auth = try await BlossomAuth.createUploadAuth(
            sha256: sha256Hex,
            size: fileSize,
            mimeType: mimeType,
            signer: signer,
            ndk: ndk,
            expiration: nil
        )

        // Build upload URL
        let uploadURL = serverURL.appendingPathComponent("upload")

        // Build request
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(try auth.authorizationHeaderValue(), forHTTPHeaderField: "Authorization")

        // Configure session with extended timeouts for large files
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 300
        sessionConfig.timeoutIntervalForResource = 1800

        // Perform streaming upload from file (doesn't load entire file into memory)
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }

        let (responseData, response) = try await session.upload(for: request, fromFile: fileURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VideoPublishingError.invalidUploadResponse
        }

        switch httpResponse.statusCode {
        case 200, 201:
            let decoder = JSONDecoder()
            let uploadDescriptor = try decoder.decode(BlossomUploadDescriptor.self, from: responseData)

            guard uploadDescriptor.sha256 == sha256Hex else {
                throw VideoPublishingError.invalidUploadResponse
            }

            return BlossomBlob(
                sha256: uploadDescriptor.sha256,
                url: uploadDescriptor.url,
                size: uploadDescriptor.size,
                type: uploadDescriptor.type,
                uploaded: Date(timeIntervalSince1970: TimeInterval(uploadDescriptor.uploaded))
            )

        default:
            throw VideoPublishingError.uploadFailed
        }
    }

    /// Computes SHA256 hash of a file using chunked reading to avoid loading the entire file into memory.
    /// Must be called from a background context to avoid blocking the main thread.
    /// Supports cooperative cancellation via Task.checkCancellation().
    private static func computeSHA256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)

        let bufferSize = 64 * 1024 // 64KB chunks
        while let data = try handle.read(upToCount: bufferSize), !data.isEmpty {
            try Task.checkCancellation()
            data.withUnsafeBytes { buffer in
                _ = CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(buffer.count))
            }
        }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)

        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
