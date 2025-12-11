import Foundation
import SwiftUI
import NDKSwiftCore
import UnifiedBlurHash
import Observation

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

@Observable
public final class PostManager {
    public var isPublishing = false
    public var publishingStatus: String = ""
    public var publishingProgress: Double = 0
    public var error: Error?
    public var lastPublishedEventId: String?

    private let ndk: NDK
    private let blossomManager: NDKBlossomServerManager

    public init(ndk: NDK) {
        self.ndk = ndk
        self.blossomManager = NDKBlossomServerManager(ndk: ndk)
        setupDefaultServers()
    }

    private func setupDefaultServers() {
        if blossomManager.userServers.isEmpty {
            for server in OlasConstants.blossomServers {
                blossomManager.addUserServer(server)
            }
        }
    }

    public func dismissError() {
        self.error = nil
        self.isPublishing = false
        self.publishingStatus = ""
    }

    public func publish(image: UIImage, caption: String) async {
        await MainActor.run {
            isPublishing = true
            publishingStatus = "Starting upload..."
            publishingProgress = 0.1
            error = nil
        }

        do {
            // Compress
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                throw PostError.imageCompressionFailed
            }

            await MainActor.run {
                publishingStatus = "Uploading image..."
                publishingProgress = 0.3
            }

            // Upload
            let blob = try await blossomManager.uploadToUserServers(data: imageData, mimeType: "image/jpeg")
            let imageUrl = blob.url

            await MainActor.run {
                publishingStatus = "Processing..."
                publishingProgress = 0.6
            }

            // Blurhash
            let dimensions = "\(Int(image.size.width))x\(Int(image.size.height))"
            let blurhash = await UnifiedBlurHash.getBlurHashString(from: image)

            await MainActor.run {
                publishingStatus = "Publishing..."
                publishingProgress = 0.8
            }

            // Publish
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

            await MainActor.run {
                lastPublishedEventId = event.id
                publishingStatus = "Done!"
                publishingProgress = 1.0
            }

            try? await Task.sleep(for: .seconds(2))

            await MainActor.run {
                isPublishing = false
                publishingStatus = ""
            }

        } catch {
            await MainActor.run {
                self.error = error
                publishingStatus = "Failed: \(error.localizedDescription)"
            }
            print("Post failed: \(error)")
        }
    }
}
