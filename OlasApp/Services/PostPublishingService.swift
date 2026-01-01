import Foundation
import NDKSwiftCore
import SwiftUI
import UnifiedBlurHash

public enum PostError: LocalizedError {
    case imageCompressionFailed
    case uploadFailed
    case invalidUploadResponse

    public var errorDescription: String? {
        switch self {
        case .imageCompressionFailed:
            return "Failed to compress image"
        case .uploadFailed:
            return "Failed to upload image"
        case .invalidUploadResponse:
            return "Invalid response from upload server"
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
        // Get user's configured servers or use defaults
        let blossomManager = NDKBlossomServerManager(ndk: ndk)
        var servers = blossomManager.userServers
        if servers.isEmpty {
            servers = OlasConstants.blossomServers
        }

        guard let serverUrl = servers.first else {
            throw PostError.uploadFailed
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
            to: serverUrl,
            ndk: ndk,
            configuration: .largeFile
        )

        await onProgress("Processing...", 0.70)
        let imageUrl = blob.url

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
                .imetaTag(url: imageUrl) { imeta in
                    imeta.dim = dimensions
                    imeta.m = "image/jpeg"
                    imeta.blurhash = blurhash
                }
        }

        await onProgress("Done!", 1.0)
        return event.id
    }
}
