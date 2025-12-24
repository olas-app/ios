import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

public struct ExploreView: View {
    let ndk: NDK

    @Environment(NDKAuthManager.self) private var authManager
    @Environment(MuteListManager.self) private var muteListManager
    @Environment(SettingsManager.self) private var settings
    @State private var viewModel: ExploreViewModel?
    @State private var selectedPost: NDKEvent?
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
                            viewModel: viewModel,
                            isSearchFocused: $isSearchFocused,
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
    @Bindable var viewModel: ExploreViewModel
    @FocusState.Binding var isSearchFocused: Bool
    let onPostTap: (NDKEvent) -> Void
    let namespace: Namespace.ID

    var body: some View {
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

            if isSearchFocused || !viewModel.searchText.isEmpty {
                SearchResultsView(
                    searchText: viewModel.searchText,
                    userResults: viewModel.filteredUserResults,
                    postResults: viewModel.filteredSearchResults
                )
            } else {
                DiscoverContentView(
                    viewModel: viewModel,
                    onPostTap: onPostTap,
                    namespace: namespace
                )
            }
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
        HStack(spacing: 12) {
            SearchField(
                searchText: $searchText,
                isSearchFocused: $isSearchFocused,
                onSearch: onSearch,
                onClear: onClear
            )

            if isSearchFocused {
                CancelButton(action: {
                    isSearchFocused = false
                    onClear()
                })
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }
}

private struct SearchField: View {
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
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

private struct CancelButton: View {
    let action: () -> Void

    var body: some View {
        Button("Cancel", action: action)
            .foregroundStyle(OlasTheme.Colors.accent)
            .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}

// MARK: - Discover Content

/// Content for the discover/trending tab
struct DiscoverContentView: View {
    @Bindable var viewModel: ExploreViewModel
    let onPostTap: (NDKEvent) -> Void
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            TabBar(selectedTab: $viewModel.selectedTab)
                .padding(.top, 8)

            if !viewModel.filteredSuggestedUsers.isEmpty {
                SuggestedUsersSection(users: viewModel.filteredSuggestedUsers)
            }

            PostGridView(posts: viewModel.filteredTrendingPosts, spacing: 2, onTap: onPostTap, namespace: namespace)
                .padding(.top, 16)
        }
    }
}

// MARK: - Suggested Users Section

struct SuggestedUsersSection: View {
    let users: [SuggestedUser]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Suggested for you")
                    .font(.headline)

                Spacer()

                Button("See All") {}
                    .font(.subheadline)
                    .foregroundStyle(OlasTheme.Colors.accent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(users) { user in
                        NavigationLink(value: user.pubkey) {
                            SuggestedUserCard(user: user)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Suggested User Card

struct SuggestedUserCard: View {
    let user: SuggestedUser

    @Environment(\.ndk) private var ndk

    var body: some View {
        VStack(spacing: 12) {
            if let ndk = ndk {
                NDKUIProfilePicture(ndk: ndk, pubkey: user.pubkey, size: 70)
                    .clipShape(Circle())

                VStack(spacing: 2) {
                    NDKUIDisplayName(ndk: ndk, pubkey: user.pubkey)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text("Suggested")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                NDKUIFollowButton(ndk: ndk, pubkey: user.pubkey, style: .compact)
            }
        }
        .frame(width: 130)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}
