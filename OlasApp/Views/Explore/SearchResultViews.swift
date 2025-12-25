import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

// MARK: - Search Results Container

/// Main container for search results
struct SearchResultsView: View {
    let searchText: String
    let userResults: [SearchUserResult]
    let postResults: [NDKEvent]

    var body: some View {
        LazyVStack(spacing: 0) {
            if searchText.isEmpty {
                SearchSuggestionsView()
            } else if userResults.isEmpty && postResults.isEmpty {
                EmptySearchView()
            } else {
                if !userResults.isEmpty {
                    UserResultsSection(users: userResults)
                }

                if !postResults.isEmpty {
                    PostResultsSection(posts: postResults)
                }
            }
        }
    }
}

// MARK: - User Results Section

/// Section displaying user search results
struct UserResultsSection: View {
    let users: [SearchUserResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Users")

            ForEach(users) { user in
                NavigationLink(value: user.pubkey) {
                    SearchUserRow(user: user)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Post Results Section

/// Section displaying post search results
struct PostResultsSection: View {
    let posts: [NDKEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Posts")

            LazyVStack(spacing: 1) {
                ForEach(posts, id: \.id) { event in
                    SearchPostRow(event: event)
                }
            }
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 16)
    }
}

// MARK: - Search User Row

struct SearchUserRow: View {
    let user: SearchUserResult

    @Environment(\.ndk) private var ndk

    var body: some View {
        HStack(spacing: 12) {
            if let ndk = ndk {
                NDKUIProfilePicture(ndk: ndk, pubkey: user.pubkey, size: 50)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    NDKUIDisplayName(ndk: ndk, pubkey: user.pubkey)
                        .font(.subheadline.weight(.semibold))

                    Text(String(user.pubkey.prefix(16)) + "...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NDKUIFollowButton(ndk: ndk, pubkey: user.pubkey, style: .compact)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Media Content Helper

private struct MediaContent {
    let thumbnailURL: URL?
    let blurhash: String?
    let accessibilityLabel: String

    init(event: NDKEvent) {
        let isVideo = event.kind == OlasConstants.EventKinds.shortVideo

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

// MARK: - Search Post Row

struct SearchPostRow: View {
    let event: NDKEvent

    @Environment(\.ndk) private var ndk

    private var media: MediaContent {
        MediaContent(event: event)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let url = media.thumbnailURL {
                PostThumbnail(
                    url: url,
                    blurhash: media.blurhash,
                    accessibilityLabel: media.accessibilityLabel
                )
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                if let ndk = ndk {
                    NDKUIDisplayName(ndk: ndk, pubkey: event.pubkey)
                        .font(.subheadline.weight(.semibold))
                }

                Text(event.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Post Thumbnail

private struct PostThumbnail: View {
    let url: URL
    let blurhash: String?
    let accessibilityLabel: String

    var body: some View {
        CachedAsyncImage(
            url: url,
            blurhash: blurhash,
            aspectRatio: 1,
            contentMode: .fill
        ) {
            Rectangle()
                .fill(Color.gray.opacity(0.1))
        }
        .frame(width: 60, height: 60)
        .cornerRadius(8)
        .clipped()
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Empty Search View

struct EmptySearchView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("No results found")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Try a different search term")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 60)
    }
}

// MARK: - Search Suggestions

struct SearchSuggestionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Try searching for")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 24)

            VStack(spacing: 0) {
                SearchSuggestionRow(icon: "person.fill", text: "Users by name or npub")
                SearchSuggestionRow(icon: "photo.fill", text: "Posts with keywords")
                SearchSuggestionRow(icon: "number", text: "Hashtags like #photography")
            }
        }
    }
}

private struct SearchSuggestionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
