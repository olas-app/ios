import Foundation
import NDKSwiftCore
import SwiftUI
import UnifiedBlurHash

public enum PostError: LocalizedError {
    case noUploadServer
    case imageCompressionFailed
    case uploadFailed

    public var errorDescription: String? {
        switch self {
        case .noUploadServer:
            return "No upload server configured. Please add a Blossom server in settings."
        case .imageCompressionFailed:
            return "Failed to compress image"
        case .uploadFailed:
            return "Failed to upload image"
        }
    }
}

/// Service for publishing posts to Nostr
public struct PostPublishingService {
    public static func publish(
        ndk: NDK,
        image: UIImage,
        caption: String,
        onProgress: @MainActor (String, Double) -> Void
    ) async throws -> String {
        let serverURL: URL
        do {
            serverURL = try BlossomServerResolver.effectiveServerURL(ndk: ndk)
        } catch is BlossomServerError {
            throw PostError.noUploadServer
        }

        // Compress and strip EXIF metadata for privacy (removes GPS, camera info, etc.)
        await onProgress("Preparing image...", 0.05)
        guard let imageData = ImageMetadataStripper.jpegDataWithoutMetadata(
            from: image,
            compressionQuality: 0.8
        ) else {
            throw PostError.imageCompressionFailed
        }

        // Upload with BlossomClient
        let client = BlossomClient()
        await onProgress("Uploading...", 0.35)

        let blob = try await client.upload(
            data: imageData,
            mimeType: "image/jpeg",
            to: serverURL.absoluteString,
            ndk: ndk,
            configuration: .largeFile
        )

        await onProgress("Processing...", 0.70)
        let imageURL = blob.url

        // Blurhash
        await onProgress("Processing...", 0.75)
        let dimensions = "\(Int(image.size.width))x\(Int(image.size.height))"
        let blurhash = await UnifiedBlurHash.getBlurHashString(from: image)

        // Publish
        await onProgress("Publishing...", 0.90)
        let (event, _) = try await ndk.publish { builder in
            builder
                .kind(OlasConstants.EventKinds.image)
                .content(caption)
                .imetaTag(url: imageURL) { imeta in
                    imeta.dim = dimensions
                    imeta.m = "image/jpeg"
                    imeta.blurhash = blurhash
                }
        }

        await onProgress("Done!", 1.0)
        return event.id
    }
}
