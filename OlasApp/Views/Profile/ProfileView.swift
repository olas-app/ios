import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

public struct ProfileView: View {
    let ndk: NDK
    let pubkey: String
    let currentUserPubkey: String?
    var sparkWalletManager: SparkWalletManager?
    var nwcWalletManager: NWCWalletManager?

    @Environment(SettingsManager.self) private var settings
    @State private var showEditProfile = false
    @State private var selectedTab: ProfileTab = .posts
    @State private var selectedPost: NDKEvent?
    @State private var followingCount: Int?
    @State private var followCountTask: Task<Void, Never>?
    @Namespace private var imageNamespace

    private var isOwnProfile: Bool {
        guard let currentUserPubkey else { return false }
        return pubkey == currentUserPubkey
    }

    public init(ndk: NDK, pubkey: String, currentUserPubkey: String? = nil, sparkWalletManager: SparkWalletManager? = nil, nwcWalletManager: NWCWalletManager? = nil) {
        self.ndk = ndk
        self.pubkey = pubkey
        self.currentUserPubkey = currentUserPubkey
        self.sparkWalletManager = sparkWalletManager
        self.nwcWalletManager = nwcWalletManager
    }

    public var body: some View {
        let profile = ndk.profile(for: pubkey)

        ZStack {
            ScrollView {
            VStack(spacing: 0) {
                // Banner
                ProfileBannerView(profile: profile)

                // Avatar + Name row
                HStack(alignment: .top, spacing: 16) {
                    NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 100)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color(.systemBackground), lineWidth: 4)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        .offset(y: -40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName)
                            .font(.system(size: 22, weight: .bold))

                        // Bio
                        if !profile.about.isEmpty {
                            Text(profile.about)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        // Stats
                        if let followingCount = followingCount {
                            Text("\(followingCount) following")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top, 12)

                    Spacer()
                }
                .padding(.horizontal, 16)

                // Action button
                if isOwnProfile {
                    Button(action: { showEditProfile = true }) {
                        Text("Edit Profile")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                // Tabs
                ProfileTabsBar(selectedTab: $selectedTab)
                    .padding(.top, 16)

                // Content grid
                switch selectedTab {
                case .posts:
                    EventGrid(
                        ndk: ndk,
                        filter: NDKFilter(
                            authors: [pubkey],
                            kinds: feedKinds,
                            limit: 50
                        ),
                        onTap: { post in
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                selectedPost = post
                            }
                        },
                        namespace: imageNamespace
                    )
                case .liked:
                    LikedPostsGrid(ndk: ndk, pubkey: pubkey, namespace: imageNamespace) { post in
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            selectedPost = post
                        }
                    }
                }
            }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(selectedPost != nil ? .hidden : .visible, for: .navigationBar)
            .task {
                followCountTask = Task {
                    await loadFollowCounts()
                }
                await followCountTask?.value
            }
            .onDisappear {
                followCountTask?.cancel()
                followCountTask = nil
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(ndk: ndk, currentProfile: profile.metadata) {
                    // Profile will auto-update via ndk.profile(for:)
                }
            }

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
        .toolbar {
            if isOwnProfile, let sparkWalletManager = sparkWalletManager, let nwcWalletManager = nwcWalletManager {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView(ndk: ndk, sparkWalletManager: sparkWalletManager, nwcWalletManager: nwcWalletManager)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    private func loadFollowCounts() async {
        // Fetch following count from user's kind 3 contact list
        let followingFilter = NDKFilter(
            authors: [pubkey],
            kinds: [Kind(3)],
            limit: 1
        )

        let followingSub = ndk.subscribe(filter: followingFilter)
        for await batch in followingSub.events {
            guard !Task.isCancelled else { break }
            if let event = batch.first {
                let pTags = event.tags.filter { $0.first == "p" }
                await MainActor.run { followingCount = pTags.count }
                break
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
}

// MARK: - Profile Components

private struct ProfileBannerView: View {
    let profile: NDKProfile

    private var gradientPlaceholder: some View {
        LinearGradient(
            colors: [Color(.systemGray4), Color(.systemGray5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        // Use Color.clear as fixed-size base to prevent .fill from expanding parent
        Color.clear
            .frame(height: 180)
            .background {
                if let bannerURL = profile.bannerURL {
                    AsyncImage(url: bannerURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        gradientPlaceholder
                    }
                } else {
                    gradientPlaceholder
                }
            }
            .clipped()
    }
}

private struct ProfileTabsBar: View {
    @Binding var selectedTab: ProfileTab
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 0) {
            ProfileTabButton(
                icon: "squareshape.split.3x3",
                isSelected: selectedTab == .posts,
                animation: animation
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = .posts
                }
            }

            ProfileTabButton(
                icon: "heart",
                isSelected: selectedTab == .liked,
                animation: animation
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = .liked
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
        }
    }
}

private struct ProfileTabButton: View {
    let icon: String
    let isSelected: Bool
    var animation: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(systemName: isSelected ? "\(icon).fill" : icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                if isSelected {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(height: 1)
                        .matchedGeometryEffect(id: "tab_indicator", in: animation)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 1)
                }
            }
        }
    }
}

// MARK: - Liked Posts Grid Component

private struct LikedPostsGrid: View {
    let ndk: NDK
    let pubkey: String
    let namespace: Namespace.ID
    let onTap: (NDKEvent) -> Void

    @State private var likedMetaSubscription: NDKMetaSubscription?

    var body: some View {
        PostGridView(
            posts: likedMetaSubscription?.events ?? [],
            spacing: 1,
            onTap: onTap,
            namespace: namespace
        )
        .task {
            await loadLikedPosts()
        }
    }

    private func loadLikedPosts() async {
        await MainActor.run {
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
}
