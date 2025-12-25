import Kingfisher
import SwiftUI
import UIKit
import UnifiedBlurHash

// MARK: - Blurhash Decoder

/// Decodes blurhash strings into UIImage placeholders
enum BlurhashDecoder {
    /// Decode a blurhash string into a UIImage
    /// - Parameters:
    ///   - blurhash: The blurhash string from NIP-68 imeta tag
    ///   - size: Target size for the decoded image (small is fine, it will be scaled)
    /// - Returns: A UIImage representing the blurred placeholder, or nil if decoding fails
    static func decode(_ blurhash: String, size: CGSize = CGSize(width: 32, height: 32)) -> UIImage? {
        return UIImage(blurHash: blurhash, size: size)
    }
}

// MARK: - CachedAsyncImage

/// Cached async image view with blurhash placeholder support (NIP-68)
/// Powered by Kingfisher for efficient disk and memory caching
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let blurhash: String?
    let aspectRatio: CGFloat?
    let contentMode: ContentMode
    let placeholder: () -> Placeholder

    @State private var blurhashImage: UIImage?

    init(
        url: URL?,
        blurhash: String? = nil,
        aspectRatio: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.blurhash = blurhash
        self.aspectRatio = aspectRatio
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        if let url {
            KFImage(url)
                .placeholder {
                    if let blurhashImage {
                        Image(uiImage: blurhashImage)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    } else {
                        placeholder()
                    }
                }
                .fade(duration: 0.2)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .onAppear {
                    decodeBlurhash()
                }
        } else {
            placeholder()
        }
    }

    private func decodeBlurhash() {
        guard blurhashImage == nil, let blurhash, !blurhash.isEmpty else { return }

        // Decode at a small size - it will be scaled up with blur effect
        let size: CGSize
        if let aspectRatio, aspectRatio > 0 {
            // Use aspect ratio to get correct proportions
            if aspectRatio > 1 {
                size = CGSize(width: 32, height: 32 / aspectRatio)
            } else {
                size = CGSize(width: 32 * aspectRatio, height: 32)
            }
        } else {
            size = CGSize(width: 32, height: 32)
        }

        blurhashImage = BlurhashDecoder.decode(blurhash, size: size)
    }
}

// MARK: - Convenience Initializers

extension CachedAsyncImage where Placeholder == ProgressView<EmptyView, EmptyView> {
    init(
        url: URL?,
        blurhash: String? = nil,
        aspectRatio: CGFloat? = nil,
        contentMode: ContentMode = .fill
    ) {
        self.init(
            url: url,
            blurhash: blurhash,
            aspectRatio: aspectRatio,
            contentMode: contentMode,
            placeholder: { ProgressView() }
        )
    }
}

extension CachedAsyncImage where Placeholder == EmptyView {
    init(
        url: URL?,
        blurhash: String? = nil,
        aspectRatio: CGFloat? = nil,
        contentMode: ContentMode = .fill
    ) {
        self.init(
            url: url,
            blurhash: blurhash,
            aspectRatio: aspectRatio,
            contentMode: contentMode,
            placeholder: { EmptyView() }
        )
    }
}

// MARK: - Legacy API Support

extension CachedAsyncImage {
    /// Legacy initializer that accepts a content closure (ignored - use modifiers on CachedAsyncImage instead)
    init<Content: View>(
        url: URL?,
        blurhash: String? = nil,
        aspectRatio: CGFloat? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            url: url,
            blurhash: blurhash,
            aspectRatio: aspectRatio,
            contentMode: .fill,
            placeholder: placeholder
        )
    }
}
