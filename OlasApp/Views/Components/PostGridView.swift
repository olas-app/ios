import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

/// Unified grid component for displaying posts in a 3-column grid layout
/// Used by ProfileView and ExploreView for consistent styling
public struct PostGridView: View {
    let posts: [NDKEvent]
    let spacing: CGFloat
    let onTap: (NDKEvent) -> Void
    let onNearEnd: ((NDKEvent) -> Void)?
    let namespace: Namespace.ID

    /// Event IDs whose images have been confirmed loadable, in order of confirmation
    @State private var loadedIds: [String] = []
    /// Event IDs already processed (loaded, failed, or no URL) — avoids re-prefetching
    @State private var processedIds: Set<String> = []

    public init(
        posts: [NDKEvent],
        spacing: CGFloat = 2,
        onTap: @escaping (NDKEvent) -> Void,
        onNearEnd: ((NDKEvent) -> Void)? = nil,
        namespace: Namespace.ID
    ) {
        self.posts = posts
        self.spacing = spacing
        self.onTap = onTap
        self.onNearEnd = onNearEnd
        self.namespace = namespace
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing),
        ]
    }

    /// Only show events whose images have actually loaded
    private var displayedPosts: [NDKEvent] {
        let postMap = Dictionary(posts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return loadedIds.compactMap { postMap[$0] }
    }

    public var body: some View {
        let displayed = displayedPosts
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(Array(displayed.enumerated()), id: \.element.id) { index, post in
                GridCell(event: post, onTap: onTap, namespace: namespace)
                    .onAppear {
                        if let onNearEnd, index >= displayed.count - 9 {
                            onNearEnd(post)
                        }
                    }
            }
        }
        .onChange(of: posts.count) {
            prefetchNewImages()
        }
        .onAppear {
            prefetchNewImages()
        }
    }

    private func prefetchNewImages() {
        for event in posts {
            let id = event.id
            guard !processedIds.contains(id) else { continue }
            processedIds.insert(id)

            guard let url = thumbnailURL(for: event) else { continue }

            KingfisherManager.shared.retrieveImage(with: url) { result in
                Task { @MainActor in
                    if case .success = result {
                        loadedIds.append(id)
                    }
                }
            }
        }
    }

    private func thumbnailURL(for event: NDKEvent) -> URL? {
        let isVideo = event.kind == OlasConstants.EventKinds.shortVideo
        if isVideo {
            let video = NDKVideo(event: event)
            return video.thumbnailURL.flatMap { URL(string: $0) }
        } else {
            let image = NDKImage(event: event)
            return image.primaryImageURL.flatMap { URL(string: $0) }
        }
    }
}

// MARK: - Grid Cell

/// Individual cell in the post grid
private struct GridCell: View {
    let event: NDKEvent
    let onTap: (NDKEvent) -> Void
    let namespace: Namespace.ID

    @State private var media: MediaContent?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let media = media {
                    MediaContentView(
                        media: media,
                        cellWidth: geometry.size.width,
                        namespace: namespace,
                        eventId: event.id
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
    let namespace: Namespace.ID
    let eventId: String

    var body: some View {
        if let url = media.thumbnailURL {
            ThumbnailImageView(
                url: url,
                blurhash: media.blurhash,
                cellWidth: cellWidth,
                accessibilityLabel: media.accessibilityLabel,
                namespace: namespace,
                eventId: eventId
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
    let namespace: Namespace.ID
    let eventId: String

    var body: some View {
        CachedAsyncImage(
            url: url,
            blurhash: blurhash,
            aspectRatio: 1,
            contentMode: .fill
        ) {
            LoadingPlaceholder()
        }
        .frame(width: cellWidth, height: cellWidth)
        .clipped()
        .matchedGeometryEffect(id: "image-\(eventId)", in: namespace)
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
