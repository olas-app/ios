import NDKSwiftCore
import SwiftUI

public struct VideosView: View {
    @State private var viewModel: VideoFeedViewModel
    @State private var currentIndex: Int? = 0
    @State private var showVideoCapture = false

    @Environment(RelayMetadataCache.self) private var relayMetadataCache
    @Environment(NDKAuthManager.self) private var authManager
    @Environment(MuteListManager.self) private var muteListManager
    @Environment(MainTabCoordinator.self) private var coordinator

    private let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
        _viewModel = State(initialValue: VideoFeedViewModel(ndk: ndk))
    }

    private var currentFeedDisplayName: String {
        switch viewModel.feedMode {
        case .following:
            return "Following"
        case .network:
            return "Network"
        case let .relay(url):
            return relayMetadataCache.displayName(for: url)
        case let .pack(pack):
            return pack.name
        case let .hashtag(tag):
            return "#\(tag)"
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.videos.isEmpty {
                    emptyState
                } else {
                    videoFeed
                }

                // Top overlay with feed selector
                VStack {
                    feedSelector
                        .padding(.top, 8)
                    Spacer()
                }

                // Floating Action Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        createButton
                            .padding(.trailing, 20)
                            .padding(.bottom, 100)
                    }
                }
            }
            .fullScreenCover(isPresented: $showVideoCapture) {
                NavigationStack {
                    VideoCaptureView(ndk: ndk)
                }
            }
        }
        .task {
            viewModel.startSubscription(muteListManager: muteListManager)

            // Fetch relay metadata
            await withTaskGroup(of: Void.self) { group in
                for relayURL in DiscoveryRelays.relays {
                    group.addTask {
                        await relayMetadataCache.fetchMetadata(for: relayURL)
                    }
                }
            }
        }
        .onDisappear {
            viewModel.stopSubscription()
        }
        .onChange(of: muteListManager.mutedPubkeys) { _, newMutedPubkeys in
            viewModel.updateForMuteList(newMutedPubkeys)
        }
        .onChange(of: coordinator.sessionData?.followList, initial: true) { _, newFollowList in
            guard viewModel.feedMode == .following else { return }
            guard let follows = newFollowList, !follows.isEmpty else { return }
            viewModel.stopSubscription()
            viewModel.startSubscription(muteListManager: muteListManager)
        }
        .onChange(of: coordinator.sessionData?.wotState.isAvailable) { _, isAvailable in
            guard viewModel.feedMode == .network else { return }
            guard isAvailable == true else { return }
            viewModel.stopSubscription()
            viewModel.startSubscription(muteListManager: muteListManager)
        }
    }

    // MARK: - Feed Selector

    private var feedSelector: some View {
        Menu {
            Button {
                viewModel.switchMode(to: .following, muteListManager: muteListManager)
            } label: {
                Label("Following", systemImage: viewModel.feedMode == .following ? "checkmark" : "")
            }

            Button {
                viewModel.switchMode(to: .network, muteListManager: muteListManager)
            } label: {
                Label("Network", systemImage: viewModel.feedMode == .network ? "checkmark" : "")
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
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(OlasTheme.Glass.Level.ultraThin.material.opacity(0.8))
            .clipShape(Capsule())
        }
    }

    // MARK: - Video Feed

    private var videoFeed: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, event in
                        VideoFeedItem(
                            event: event,
                            ndk: ndk,
                            isVisible: index == (currentIndex ?? 0)
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentIndex)
        }
        .ignoresSafeArea()
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.isLoading {
            ProgressView()
                .tint(.white)
        } else if let error = viewModel.error {
            ContentUnavailableView(
                "Unable to load videos",
                systemImage: "wifi.slash",
                description: Text(error.localizedDescription)
            )
            .foregroundStyle(.white)
        } else {
            ContentUnavailableView(
                "No videos yet",
                systemImage: "play.rectangle",
                description: Text(viewModel.feedMode == .network
                    ? "Your web of trust is still loading or has no videos"
                    : "Follow some accounts or check back later")
            )
            .foregroundStyle(.white)
        }
    }

    // MARK: - Create Button (FAB)

    private var createButton: some View {
        Button {
            showVideoCapture = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "00BF8F"), Color(hex: "667EEA")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(hex: "00BF8F").opacity(0.4), radius: 12, y: 4)
                )
        }
    }
}
