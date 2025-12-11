// FeedView.swift
import SwiftUI
import NDKSwiftCore

public struct FeedView: View {
    @State private var viewModel: FeedViewModel
    @Environment(RelayMetadataCache.self) private var relayMetadataCache
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var muteListManager: MuteListManager
    private let ndk: NDK

    @State private var navigationPath = NavigationPath()

    public init(ndk: NDK, settings: SettingsManager) {
        self.ndk = ndk
        self.viewModel = FeedViewModel(ndk: ndk, settings: settings)
    }

    private var currentFeedDisplayName: String {
        switch viewModel.feedMode {
        case .following:
            return "Following"
        case .relay(let url):
            return relayMetadataCache.displayName(for: url)
        }
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                ForEach(viewModel.posts, id: \.id) { event in
                    PostCard(event: event, ndk: ndk) { pubkey in
                        navigationPath.append(pubkey)
                    }
                    .equatable()
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
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
            }
            .navigationDestination(for: String.self) { pubkey in
                ProfileView(ndk: ndk, pubkey: pubkey, currentUserPubkey: authViewModel.currentUser?.pubkey)
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
