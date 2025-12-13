import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

/// Unified grid component for displaying posts in a 3-column grid layout
/// Used by ProfileView and ExploreView for consistent styling
public struct PostGridView: View {
    let posts: [NDKEvent]
    let spacing: CGFloat
    let onTap: (NDKEvent) -> Void

    /// Creates a post grid view
    /// - Parameters:
    ///   - posts: Array of NDKEvent posts to display
    ///   - spacing: Space between grid items (default: 2)
    ///   - onTap: Closure called when a post is tapped
    public init(
        posts: [NDKEvent],
        spacing: CGFloat = 2,
        onTap: @escaping (NDKEvent) -> Void
    ) {
        self.posts = posts
        self.spacing = spacing
        self.onTap = onTap
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing),
        ]
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(posts, id: \.id) { post in
                GridCell(event: post, onTap: onTap)
            }
        }
    }
}

// MARK: - Grid Cell

/// Individual cell in the post grid
private struct GridCell: View {
    let event: NDKEvent
    let onTap: (NDKEvent) -> Void

    @State private var media: MediaContent?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let media = media {
                    MediaContentView(
                        media: media,
                        cellWidth: geometry.size.width
                    )
                } else {
                    LoadingPlaceholder()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap(event)
        }
        .task {
            await loadMedia()
        }
    }

    private func loadMedia() async {
        let content = MediaContent(event: event)
        await MainActor.run {
            self.media = content
        }
    }
}

// MARK: - Media Content Model

/// Represents the media content of a post (image or video)
private struct MediaContent {
    let type: MediaType
    let thumbnailURL: URL?
    let blurhash: String?
    let accessibilityLabel: String

    enum MediaType {
        case image
        case video
    }

    init(event: NDKEvent) {
        let isVideo = event.kind == OlasConstants.EventKinds.shortVideo
        type = isVideo ? .video : .image

        if isVideo {
            let video = NDKVideo(event: event)
            thumbnailURL = Self.parseURL(from: video.thumbnailURL)
            blurhash = video.primaryBlurhash
            accessibilityLabel = video.primaryAlt ?? "Video"
        } else {
            let image = NDKImage(event: event)
            thumbnailURL = Self.parseURL(from: image.primaryImageURL)
            blurhash = image.primaryBlurhash
            accessibilityLabel = image.primaryAlt ?? "Post image"
        }
    }

    private static func parseURL(from string: String?) -> URL? {
        guard let string = string else { return nil }
        return URL(string: string)
    }
}

// MARK: - Media Content View

/// Displays the media content with appropriate fallbacks
private struct MediaContentView: View {
    let media: MediaContent
    let cellWidth: CGFloat

    var body: some View {
        if let url = media.thumbnailURL {
            ThumbnailImageView(
                url: url,
                blurhash: media.blurhash,
                cellWidth: cellWidth,
                accessibilityLabel: media.accessibilityLabel
            )
            .overlay(alignment: .bottomTrailing) {
                if media.type == .video {
                    VideoIndicator()
                }
            }
        } else {
            FallbackView(type: media.type)
        }
    }
}

// MARK: - Thumbnail Image View

/// Displays a thumbnail image with blurhash placeholder
private struct ThumbnailImageView: View {
    let url: URL
    let blurhash: String?
    let cellWidth: CGFloat
    let accessibilityLabel: String

    var body: some View {
        CachedAsyncImage(
            url: url,
            blurhash: blurhash,
            aspectRatio: 1
        ) { loadedImage in
            loadedImage
                .resizable()
                .scaledToFill()
                .frame(width: cellWidth, height: cellWidth)
                .clipped()
        } placeholder: {
            LoadingPlaceholder()
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Video Indicator

/// Small play button overlay for video thumbnails
private struct VideoIndicator: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.caption)
            .foregroundStyle(.white)
            .padding(4)
            .background(.black.opacity(0.5))
            .clipShape(Circle())
            .padding(6)
    }
}

// MARK: - Fallback View

/// Displayed when no thumbnail is available
private struct FallbackView: View {
    let type: MediaContent.MediaType

    var body: some View {
        switch type {
        case .video:
            VideoPlaceholder()
        case .image:
            ImagePlaceholder()
        }
    }
}

/// Placeholder for videos without thumbnails
private struct VideoPlaceholder: View {
    var body: some View {
        LinearGradient(
            colors: [
                OlasTheme.Colors.accent.opacity(0.8),
                OlasTheme.Colors.accent.opacity(0.8),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.9))
        }
        .accessibilityLabel("Video")
    }
}

/// Placeholder for images that failed to load
private struct ImagePlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Image not available")
    }
}

/// Loading placeholder during initial load
private struct LoadingPlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .overlay {
                ProgressView()
                    .tint(OlasTheme.Colors.accent)
            }
    }
}
