import Foundation
import SwiftUI
import NDKSwiftCore
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
    private let ndk: NDK
    private let blossomManager: NDKBlossomServerManager

    public init(ndk: NDK) {
        self.ndk = ndk
        var manager = NDKBlossomServerManager(ndk: ndk)

        // Initialize with default servers if none configured
        if manager.userServers.isEmpty {
            for server in OlasConstants.blossomServers {
                manager.addUserServer(server)
            }
        }

        self.blossomManager = manager
    }

    public func publish(
        image: UIImage,
        caption: String,
        onProgress: @MainActor (String, Double) -> Void
    ) async throws -> String {
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
        let event = try await ndk.publish { builder in
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
