import AVFoundation
import Foundation
import NDKSwiftCore
import SwiftUI
import UnifiedBlurHash

enum VideoPublishingError: LocalizedError {
    case videoCompressionFailed
    case thumbnailGenerationFailed
    case uploadFailed
    case invalidUploadResponse
    case publishFailed

    var errorDescription: String? {
        switch self {
        case .videoCompressionFailed:
            return "Failed to compress video"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        case .uploadFailed:
            return "Failed to upload video"
        case .invalidUploadResponse:
            return "Invalid response from upload server"
        case .publishFailed:
            return "Failed to publish to Nostr"
        }
    }
}

/// Service for publishing videos to Nostr
struct VideoPublishingService {
    static func publish(
        ndk: NDK,
        videoURL: URL,
        caption: String,
        videoMode: VideoCaptureView.VideoMode,
        onProgress: @MainActor (String, Double) -> Void
    ) async throws -> String {
        // Get user's configured servers or use defaults
        let blossomManager = NDKBlossomServerManager(ndk: ndk)
        var servers = blossomManager.userServers
        if servers.isEmpty {
            servers = OlasConstants.blossomServers
        }

        guard let serverUrl = servers.first else {
            throw VideoPublishingError.uploadFailed
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
            to: serverUrl,
            ndk: ndk,
            configuration: .default
        )

        // 5. Upload video (uses largeFile config with extended timeouts)
        await onProgress("Uploading video...", 0.30)
        let videoData = try Data(contentsOf: videoURL)

        let videoBlob = try await client.upload(
            data: videoData,
            mimeType: "video/mp4",
            to: serverUrl,
            ndk: ndk,
            configuration: .largeFile
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
}
