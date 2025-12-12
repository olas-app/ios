import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

public struct ProfileView: View {
    let ndk: NDK
    let pubkey: String
    let currentUserPubkey: String?
    var sparkWalletManager: SparkWalletManager?

    @Environment(SettingsManager.self) private var settings
    @State private var profile: NDKUserMetadata?
    @State private var showEditProfile = false
    @State private var selectedTab: ProfileTab = .posts
    @State private var selectedPost: NDKEvent?

    private var isOwnProfile: Bool {
        guard let currentUserPubkey else { return false }
        return pubkey == currentUserPubkey
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

                // Action button
                if isOwnProfile {
                    Button(action: { showEditProfile = true }) {
                        Text("Edit Profile")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray5))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }

                // Tabs
                ProfileTabsBar(selectedTab: $selectedTab)

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
                        onTap: { post in selectedPost = post }
                    )
                case .liked:
                    LikedPostsGrid(ndk: ndk, pubkey: pubkey) { post in
                        selectedPost = post
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            Task { await loadProfile() }
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

                TabButton(title: "Liked", isSelected: selectedTab == .liked) {
                    selectedTab = .liked
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

// MARK: - Liked Posts Grid Component

private struct LikedPostsGrid: View {
    let ndk: NDK
    let pubkey: String
    let onTap: (NDKEvent) -> Void

    @State private var likedMetaSubscription: NDKMetaSubscription?

    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(likedMetaSubscription?.events ?? []) { event in
                GridItemView(event: event, onTap: onTap)
            }
        }
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
