import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

public struct ProfileView: View {
    let ndk: NDK
    let pubkey: String
    let currentUserPubkey: String?
    var sparkWalletManager: SparkWalletManager?

    @EnvironmentObject private var muteListManager: MuteListManager
    @Environment(SettingsManager.self) private var settings
    @State private var profile: NDKUserMetadata?
    @State private var posts: [NDKEvent] = []
    @State private var likedMetaSubscription: NDKMetaSubscription?
    @State private var followingCount = 0
    @State private var showEditProfile = false
    @State private var selectedTab: ProfileTab = .posts
    @State private var selectedPost: NDKEvent?

    private var currentPosts: [NDKEvent] {
        selectedTab == .posts ? posts : (likedMetaSubscription?.events ?? [])
    }

    private var isOwnProfile: Bool {
        guard let currentUserPubkey else { return false }
        return pubkey == currentUserPubkey
    }

    private var isMuted: Bool {
        muteListManager.isMuted(pubkey)
    }

    public init(ndk: NDK, pubkey: String, currentUserPubkey: String? = nil, sparkWalletManager: SparkWalletManager? = nil) {
        self.ndk = ndk
        self.pubkey = pubkey
        self.currentUserPubkey = currentUserPubkey
        self.sparkWalletManager = sparkWalletManager
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Banner
                ProfileBannerView(profile: profile)

                // Profile header - avatar and name side by side
                HStack(alignment: .center, spacing: 16) {
                    ProfileAvatarView(profile: profile)
                        .padding(.leading, 20)
                        .offset(y: -48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile?.name ?? "Unknown")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.primary)

                        if let about = profile?.about, !about.isEmpty {
                            Text(about)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.trailing, 20)

                    Spacer()
                }
                .padding(.top, 8)

                // Stats and action button
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 32) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(currentPosts.count)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.primary)
                            Text("Posts")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(followingCount)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.primary)
                            Text("Following")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(action: isOwnProfile ? { showEditProfile = true } : { Task { await toggleMute() } }) {
                        Text(isOwnProfile ? "Edit Profile" : (isMuted ? "Unmute" : "Mute"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray5))
                            .cornerRadius(10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                // Tabs
                ProfileTabsBar(selectedTab: $selectedTab)

                // Content grid
                PostsGridView(posts: currentPosts) { post in
                    selectedPost = post
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await loadProfile()
            await loadPosts()
            await loadLikedPosts()
            await loadFollowing()
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileView(ndk: ndk, currentProfile: profile) {
                Task { await loadProfile() }
            }
        }
        .fullScreenCover(item: $selectedPost) { post in
            FullscreenPostViewer(
                event: post,
                ndk: ndk,
                isPresented: Binding(
                    get: { selectedPost != nil },
                    set: { if !$0 { selectedPost = nil } }
                )
            )
        }
        .toolbar {
            if isOwnProfile, let sparkWalletManager = sparkWalletManager {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView(ndk: ndk, sparkWalletManager: sparkWalletManager)) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private func loadProfile() async {
        for await metadata in await ndk.profileManager.subscribe(for: pubkey, maxAge: 60) {
            await MainActor.run {
                self.profile = metadata
            }
        }
    }

    private var feedKinds: [Kind] {
        var kinds: [Kind] = [OlasConstants.EventKinds.image]
        if settings.showVideos {
            kinds.append(OlasConstants.EventKinds.shortVideo)
        }
        return kinds
    }

    private func loadPosts() async {
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: feedKinds,
            limit: 50
        )

        let subscription = ndk.subscribe(filter: filter)

        // Stream posts as they arrive - insert sorted to maintain order
        for await event in subscription.events {
            // Insert in sorted position (newest first)
            let insertIndex = posts.firstIndex { event.createdAt > $0.createdAt } ?? posts.endIndex
            posts.insert(event, at: insertIndex)
        }
    }

    private func loadLikedPosts() async {
        await MainActor.run {
            // Use metaSubscribe to get posts the user has liked (reacted to)
            let likeFilter = NDKFilter(
                authors: [pubkey],
                kinds: [Kind(7)],
                limit: 100
            )

            likedMetaSubscription = ndk.metaSubscribe(
                filter: likeFilter,
                sort: .tagTime
            )
        }
    }

    private func loadFollowing() async {
        let user = NDKUser(pubkey: pubkey)
        await user.setNdk(ndk)

        do {
            let follows = try await user.follows()
            await MainActor.run {
                self.followingCount = follows.count
            }
        } catch {
            await MainActor.run {
                self.followingCount = 0
            }
        }
    }

    private func toggleMute() async {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        do {
            if isMuted {
                try await muteListManager.unmute(pubkey)
            } else {
                try await muteListManager.mute(pubkey)
            }
        } catch {
            // Mute/unmute failed silently
        }
    }
}

// MARK: - Profile Components

private struct ProfileBannerView: View {
    let profile: NDKUserMetadata?

    var body: some View {
        Group {
            if let bannerURL = profile?.banner, let url = URL(string: bannerURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray6))
                }
            } else {
                Rectangle()
                    .fill(Color(.systemGray6))
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

private struct ProfileAvatarView: View {
    let profile: NDKUserMetadata?

    var body: some View {
        Group {
            if let pictureURL = profile?.picture, let url = URL(string: pictureURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color(.systemGray5))
                        .overlay(
                            Text(String(profile?.name?.prefix(1) ?? "?").uppercased())
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(.primary)
                        )
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Text(String(profile?.name?.prefix(1) ?? "?").uppercased())
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.primary)
                    )
            }
        }
        .overlay(
            Circle()
                .stroke(Color(.systemBackground), lineWidth: 4)
        )
        .shadow(color: Color(.label).opacity(0.3), radius: 8, y: 4)
    }
}

private struct ProfileTabsBar: View {
    @Binding var selectedTab: ProfileTab

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabButton(title: "Posts", isSelected: selectedTab == .posts) {
                    selectedTab = .posts
                }

                TabButton(title: "Liked", isSelected: selectedTab == .replies) {
                    selectedTab = .replies
                }
            }

            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
        }
    }
}

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)

                Rectangle()
                    .fill(isSelected ? Color.primary : Color.clear)
                    .frame(height: 1)
            }
        }
    }
}

private struct PostsGridView: View {
    let posts: [NDKEvent]
    let onTap: (NDKEvent) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(posts) { post in
                GridItemView(post: post, onTap: onTap)
            }
        }
    }
}

private struct GridItemView: View {
    let post: NDKEvent
    let onTap: (NDKEvent) -> Void

    private var image: NDKImage {
        NDKImage(event: post)
    }

    var body: some View {
        Group {
            if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(
                    url: url,
                    blurhash: image.primaryBlurhash,
                    aspectRatio: image.primaryAspectRatio
                ) { loadedImage in
                    loadedImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                }
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .onTapGesture {
            onTap(post)
        }
    }
}
