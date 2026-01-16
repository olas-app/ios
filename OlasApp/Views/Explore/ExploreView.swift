import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

public struct ExploreView: View {
    let ndk: NDK

    @Environment(NDKAuthManager.self) private var authManager
    @Environment(MuteListManager.self) private var muteListManager
    @Environment(SettingsManager.self) private var settings
    @Environment(SavedFeedSourcesManager.self) private var feedSourcesManager
    @State private var viewModel: ExploreViewModel?
    @State private var selectedPost: NDKEvent?
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool
    @Namespace private var imageNamespace

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    if let viewModel = viewModel {
                        ExploreContentView(
                            ndk: ndk,
                            viewModel: viewModel,
                            onPostTap: { post in
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                    selectedPost = post
                                }
                            },
                            namespace: imageNamespace
                        )
                    } else {
                        ProgressView()
                    }
                }
                .navigationTitle("Explore")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.large)
                #endif
                    .navigationDestination(for: String.self) { pubkey in
                        ProfileView(ndk: ndk, pubkey: pubkey, currentUserPubkey: authManager.activePubkey)
                    }
                    .navigationDestination(for: FollowPack.self) { pack in
                        FollowPackFeedView(ndk: ndk, pack: pack)
                    }
                    .toolbar(selectedPost != nil ? .hidden : .visible, for: .navigationBar)
                    .toolbar(selectedPost != nil ? .hidden : .visible, for: .tabBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isSearchActive = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.body.weight(.medium))
                            }
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
            .task {
                await initializeViewModel()
            }
            .sheet(isPresented: $isSearchActive) {
                if let viewModel = viewModel {
                    SearchSheet(
                        ndk: ndk,
                        viewModel: viewModel,
                        isSearchFocused: $isSearchFocused,
                        onDismiss: { isSearchActive = false }
                    )
                }
            }
        }
    }

    private func initializeViewModel() async {
        let vm = ExploreViewModel(
            ndk: ndk,
            settings: settings,
            muteListManager: muteListManager
        )
        await MainActor.run {
            self.viewModel = vm
        }
        await vm.loadDiscoverContent()
    }
}

// MARK: - Explore Content

/// Main content view for explore
private struct ExploreContentView: View {
    let ndk: NDK
    @Bindable var viewModel: ExploreViewModel
    let onPostTap: (NDKEvent) -> Void
    let namespace: Namespace.ID

    var body: some View {
        DiscoverContentView(
            ndk: ndk,
            viewModel: viewModel,
            onPostTap: onPostTap,
            namespace: namespace
        )
    }
}

// MARK: - Search Sheet

private struct SearchSheet: View {
    let ndk: NDK
    @Bindable var viewModel: ExploreViewModel
    @FocusState.Binding var isSearchFocused: Bool
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(
                    searchText: $viewModel.searchText,
                    isSearchFocused: $isSearchFocused,
                    onSearch: { query in
                        Task { await viewModel.performSearch(query: query) }
                    },
                    onClear: {
                        viewModel.clearSearch()
                    }
                )

                if !viewModel.searchText.isEmpty {
                    SearchResultsView(
                        searchText: viewModel.searchText,
                        userResults: viewModel.filteredUserResults,
                        postResults: viewModel.filteredSearchResults
                    )
                } else {
                    ContentUnavailableView(
                        "Search",
                        systemImage: "magnifyingglass",
                        description: Text("Search for users or posts")
                    )
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        viewModel.clearSearch()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            isSearchFocused = true
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var searchText: String
    @FocusState.Binding var isSearchFocused: Bool
    let onSearch: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)

            TextField("Search users or posts...", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .onChange(of: searchText) { _, newValue in
                    onSearch(newValue)
                }

            if !searchText.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassBackground(level: .ultraThin, cornerRadius: OlasTheme.Glass.cornerRadius)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Discover Content

/// Content for the discover/trending tab
struct DiscoverContentView: View {
    let ndk: NDK
    @Bindable var viewModel: ExploreViewModel
    let onPostTap: (NDKEvent) -> Void
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            // Follow Packs Section
            if !viewModel.followPacks.isEmpty {
                FollowPacksSection(ndk: ndk, packs: viewModel.followPacks)
            }

            TabBar(selectedTab: $viewModel.selectedTab)
                .padding(.top, 8)

            PostGridView(posts: viewModel.filteredTrendingPosts, spacing: 2, onTap: onPostTap, namespace: namespace)
                .padding(.top, 16)
        }
    }
}

// MARK: - Follow Packs Section

struct FollowPacksSection: View {
    let ndk: NDK
    let packs: [FollowPack]

    @State private var showAllPacks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Text("👥")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 1, green: 0.42, blue: 0.42), Color(red: 1, green: 0.56, blue: 0.33)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("Follow Packs")
                        .font(.system(size: 20, weight: .bold))
                }

                Spacer()

                Button {
                    showAllPacks = true
                } label: {
                    Text("See All")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(OlasTheme.Colors.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(packs) { pack in
                        NavigationLink(value: pack) {
                            FeaturedFollowPackCard(ndk: ndk, pack: pack)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 16)
        .navigationDestination(isPresented: $showAllPacks) {
            FollowPacksListView(ndk: ndk, packs: packs)
        }
    }
}

// MARK: - Featured Follow Pack Card

struct FeaturedFollowPackCard: View {
    let ndk: NDK
    let pack: FollowPack

    @State private var creatorProfile: NDKProfile?

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background - image or gradient fallback
            background

            // Gradient overlay for text readability
            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Floating avatars in top-right
            avatarStack
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(16)

            // Content at bottom
            content
        }
        .frame(width: 280, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task {
            creatorProfile = ndk.profile(for: pack.creatorPubkey)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
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
    }

    private var gradientBackground: some View {
        GeometryReader { _ in
            ZStack {
                LinearGradient(
                    colors: baseGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(accentColor1.opacity(0.4))
                    .blur(radius: 40)
                    .frame(width: 150, height: 150)
                    .offset(x: -60, y: 60)

                Circle()
                    .fill(accentColor2.opacity(0.3))
                    .blur(radius: 50)
                    .frame(width: 120, height: 120)
                    .offset(x: 80, y: -40)
            }
        }
    }

    private var baseGradientColors: [Color] {
        let hash = pack.name.hashValue
        let hue1 = Double(abs(hash) % 360) / 360.0
        return [
            Color(hue: hue1, saturation: 0.2, brightness: 0.15),
            Color(hue: hue1, saturation: 0.3, brightness: 0.2)
        ]
    }

    private var accentColor1: Color {
        let hash = pack.name.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.8)
    }

    private var accentColor2: Color {
        let hash = pack.name.hashValue
        let hue = Double(abs(hash >> 8) % 360) / 360.0
        return Color(hue: hue, saturation: 0.8, brightness: 0.7)
    }

    // MARK: - Avatar Stack

    private var avatarStack: some View {
        HStack(spacing: -12) {
            ForEach(Array(pack.pubkeys.prefix(3).enumerated()), id: \.element) { _, pubkey in
                NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 36)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.3), lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }

            if pack.memberCount > 3 {
                Text("+\(pack.memberCount - 3)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial.opacity(0.8))
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.3), lineWidth: 3)
                    }
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pack.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .lineLimit(1)

            HStack(spacing: 4) {
                Text("by")
                    .foregroundStyle(.white.opacity(0.7))
                Text(creatorProfile?.displayName ?? "...")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .font(.system(size: 14))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

