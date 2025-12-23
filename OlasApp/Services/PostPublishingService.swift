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
        let blossomManager = NDKBlossomServerManager(ndk: ndk)

        // Initialize with default servers if none configured
        if blossomManager.userServers.isEmpty {
            for server in OlasConstants.blossomServers {
                blossomManager.addUserServer(server)
            }
        }

        // Compress
        await onProgress("Starting upload...", 0.1)
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw PostError.imageCompressionFailed
        }

        // Upload
        await onProgress("Uploading image...", 0.3)
        let blob = try await blossomManager.uploadToUserServers(data: imageData, mimeType: "image/jpeg")
        let imageUrl = blob.url

        // Blurhash
        await onProgress("Processing...", 0.6)
        let dimensions = "\(Int(image.size.width))x\(Int(image.size.height))"
        let blurhash = await UnifiedBlurHash.getBlurHashString(from: image)

        // Publish
        await onProgress("Publishing...", 0.8)
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
