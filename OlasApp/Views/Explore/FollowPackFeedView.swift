import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

/// View that displays a follow pack's content and allows saving/unsaving
struct FollowPackFeedView: View {
    let ndk: NDK
    let pack: FollowPack

    @Environment(SavedFeedSourcesManager.self) private var feedSourcesManager
    @Environment(MuteListManager.self) private var muteListManager
    @Environment(SettingsManager.self) private var settings

    @State private var posts: [NDKEvent] = []
    @State private var selectedPost: NDKEvent?
    @State private var packFeedTask: Task<Void, Never>?
    @Namespace private var imageNamespace

    private var isSaved: Bool {
        feedSourcesManager.isPacked(pack.id)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PackHeader(ndk: ndk, pack: pack)

                PostGridView(
                    posts: filteredPosts,
                    spacing: 2,
                    onTap: { post in
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            selectedPost = post
                        }
                    },
                    namespace: imageNamespace
                )
                .padding(.top, 16)
            }
        }
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleSaved()
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(isSaved ? OlasTheme.Colors.accent : .primary)
                }
            }
        }
        .overlay {
            if let post = selectedPost {
                FullscreenPostViewer(
                    event: post,
                    ndk: ndk,
                    isPresented: Binding(
                        get: { selectedPost != nil },
                        set: { if !$0 { selectedPost = nil } }
                    ),
                    namespace: imageNamespace
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .task {
            packFeedTask = Task {
                await loadPackPosts()
            }
            await packFeedTask?.value
        }
        .onDisappear {
            packFeedTask?.cancel()
            packFeedTask = nil
        }
    }

    private var filteredPosts: [NDKEvent] {
        posts.filter { !muteListManager.isMuted($0.pubkey) }
    }

    private var feedKinds: [Kind] {
        var kinds: [Kind] = [OlasConstants.EventKinds.image]
        if settings.showVideos {
            kinds.append(OlasConstants.EventKinds.shortVideo)
        }
        return kinds
    }

    private func toggleSaved() {
        if isSaved {
            feedSourcesManager.removePack(id: pack.id)
        } else {
            feedSourcesManager.savePack(pack)
        }
    }

    private func loadPackPosts() async {
        let filter = NDKFilter(
            authors: pack.pubkeys,
            kinds: feedKinds,
            limit: 100
        )

        let subscription = ndk.subscribe(
            filter: filter,
            subscriptionId: "pack-feed-\(pack.id)",
            closeOnEose: false
        )

        for await events in subscription.events {
            guard !Task.isCancelled else { break }
            let combined = posts + events
            posts = combined.sorted { $0.createdAt > $1.createdAt }
        }
    }
}

// MARK: - Pack Header

private struct PackHeader: View {
    let ndk: NDK
    let pack: FollowPack

    var body: some View {
        VStack(spacing: 16) {
            // Background image or gradient
            ZStack(alignment: .bottom) {
                if let imageURLString = pack.image, let imageURL = URL(string: imageURLString) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            gradientBackground
                        @unknown default:
                            gradientBackground
                        }
                    }
                } else {
                    gradientBackground
                }

                // Gradient overlay
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: 160)
            .clipped()

            VStack(spacing: 12) {
                // Member avatars
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: -8) {
                        ForEach(Array(pack.pubkeys.prefix(10).enumerated()), id: \.element) { _, pubkey in
                            NavigationLink(value: pubkey) {
                                NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 44)
                                    .overlay {
                                        Circle()
                                            .stroke(Color(.systemBackground), lineWidth: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                        }

                        if pack.memberCount > 10 {
                            Text("+\(pack.memberCount - 10)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Pack info
                VStack(spacing: 4) {
                    Text("\(pack.memberCount) members")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let description = pack.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    private var gradientBackground: some View {
        LinearGradient(
            colors: baseGradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var baseGradientColors: [Color] {
        let hash = pack.name.hashValue
        let hue1 = Double(abs(hash) % 360) / 360.0
        return [
            Color(hue: hue1, saturation: 0.3, brightness: 0.25),
            Color(hue: hue1, saturation: 0.4, brightness: 0.35)
        ]
    }
}
