// FeedView.swift
import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

public struct FeedView: View {
    @State private var viewModel: FeedViewModel
    @Environment(RelayMetadataCache.self) private var relayMetadataCache
    @Environment(NDKAuthManager.self) private var authManager
    @Environment(MuteListManager.self) private var muteListManager
    @Environment(SparkWalletManager.self) private var sparkWalletManager
    @Environment(NWCWalletManager.self) private var nwcWalletManager
    @Environment(SavedFeedSourcesManager.self) private var feedSourcesManager
    @Environment(TabBarState.self) private var tabBarState: TabBarState?
    private let ndk: NDK

    @State private var navigationPath = NavigationPath()

    public init(ndk: NDK, settings: SettingsManager) {
        self.ndk = ndk
        viewModel = FeedViewModel(ndk: ndk, settings: settings)
    }

    private var currentFeedDisplayName: String {
        switch viewModel.feedMode {
        case .following:
            return "Following"
        case let .relay(url):
            return relayMetadataCache.displayName(for: url)
        case let .pack(pack):
            return pack.name
        }
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.posts, id: \.id) { event in
                        PostCard(event: event, ndk: ndk) { pubkey in
                            navigationPath.append(pubkey)
                        }
                        .equatable()
                    }
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: -geometry.frame(in: .named("feedScroll")).origin.y
                        )
                    }
                )
            }
            .coordinateSpace(name: "feedScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                tabBarState?.updateScrollOffset(offset)
            }
            .refreshable {
                viewModel.stopSubscription()
                viewModel.startSubscription(muteListManager: muteListManager)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Button {
                            viewModel.switchMode(to: .following, muteListManager: muteListManager)
                        } label: {
                            Label("Following", systemImage: viewModel.feedMode == .following ? "checkmark" : "")
                        }

                        Divider()

                        ForEach(DiscoveryRelays.relays, id: \.self) { relayURL in
                            Button {
                                viewModel.switchMode(to: .relay(url: relayURL), muteListManager: muteListManager)
                            } label: {
                                let isSelected = viewModel.feedMode == .relay(url: relayURL)
                                Label(relayMetadataCache.displayName(for: relayURL), systemImage: isSelected ? "checkmark" : "")
                            }
                        }

                        if !feedSourcesManager.savedPacks.isEmpty {
                            Divider()

                            ForEach(feedSourcesManager.savedPacks) { pack in
                                Button {
                                    viewModel.switchMode(to: .pack(pack), muteListManager: muteListManager)
                                } label: {
                                    let isSelected: Bool = {
                                        if case .pack(let selectedPack) = viewModel.feedMode {
                                            return selectedPack.id == pack.id
                                        }
                                        return false
                                    }()
                                    Label(pack.name, systemImage: isSelected ? "checkmark" : "")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(currentFeedDisplayName)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.primary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if let pubkey = authManager.activePubkey {
                        NavigationLink {
                            ProfileView(ndk: ndk, pubkey: pubkey, currentUserPubkey: pubkey, sparkWalletManager: sparkWalletManager, nwcWalletManager: nwcWalletManager)
                        } label: {
                            NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 28)
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .navigationDestination(for: String.self) { pubkey in
                ProfileView(ndk: ndk, pubkey: pubkey, currentUserPubkey: authManager.activePubkey)
            }
        }
        .task {
            // Start subscription
            viewModel.startSubscription(muteListManager: muteListManager)

            // Fetch relay metadata in parallel
            await withTaskGroup(of: Void.self) { group in
                for relayURL in DiscoveryRelays.relays {
                    group.addTask {
                        await relayMetadataCache.fetchMetadata(for: relayURL)
                    }
                }
            }
        }
        .onDisappear {
            // Stop subscription when view disappears
            viewModel.stopSubscription()
        }
        .onChange(of: muteListManager.mutedPubkeys) { _, newMutedPubkeys in
            // Remove muted users' posts from feed
            viewModel.updateForMuteList(newMutedPubkeys)
        }
        .overlay {
            if viewModel.isLoading && viewModel.posts.isEmpty {
                ProgressView()
            }

            if let error = viewModel.error {
                ContentUnavailableView(
                    "Unable to load feed",
                    systemImage: "wifi.slash",
                    description: Text(error.localizedDescription)
                )
            }

            if !viewModel.isLoading && viewModel.posts.isEmpty && viewModel.error == nil {
                ContentUnavailableView(
                    "No posts yet",
                    systemImage: "photo.on.rectangle",
                    description: Text("Follow some accounts or check back later")
                )
            }
        }
    }
}
