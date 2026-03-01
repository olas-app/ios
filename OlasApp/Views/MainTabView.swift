import NDKSwiftCore
import SwiftUI

public struct MainTabView: View {
    @Environment(NDKAuthManager.self) private var authManager
    @Environment(SettingsManager.self) private var settings
    @Environment(PublishingState.self) private var publishingState

    @State private var coordinator: MainTabCoordinator
    @State private var selectedTab: MainTab = .home
    @State private var lastContentTab: MainTab = .home
    @State private var showCreatePost = false

    private let ndk: NDK
    private let sparkWalletManager: SparkWalletManager
    private let nwcWalletManager: NWCWalletManager

    public init(ndk: NDK, sparkWalletManager: SparkWalletManager, nwcWalletManager: NWCWalletManager) {
        self.ndk = ndk
        self._coordinator = State(initialValue: MainTabCoordinator(ndk: ndk))
        self.sparkWalletManager = sparkWalletManager
        self.nwcWalletManager = nwcWalletManager
    }

    public var body: some View {
        tabContent
        .tint(.primary)
        .fullScreenCover(isPresented: $showCreatePost) {
            CreatePostView(ndk: ndk)
        }
        .task {
            await coordinator.performSetup(
                userPubkey: authManager.activePubkey,
                muteListSources: settings.muteListSources,
                walletType: settings.walletType
            )
        }
        .onChange(of: settings.muteListSources) { _, newSources in
            coordinator.updateMuteListSources(newSources)
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            if newTab == .createPost {
                selectedTab = lastContentTab
                showCreatePost = true
            } else {
                lastContentTab = newTab
            }
        }
        .environment(coordinator)
        .environment(coordinator.walletViewModel)
        .environment(coordinator.muteListManager)
        .environment(sparkWalletManager)
        .environment(nwcWalletManager)
        .overlay(alignment: .topLeading) {
            if settings.showRelayIndicator {
                RelayConnectionIndicatorButton(ndk: ndk)
                    .padding(.top, 6)
                    .padding(.leading, 8)
            }
        }
        .overlay(alignment: .top) {
            PublishingBannerOverlay(publishingState: publishingState)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            FeedView(ndk: ndk, settings: settings)
                .tag(MainTab.home)
                .tabItem {
                    Label(MainTab.home.label, systemImage: MainTab.home.selectedIcon)
                }

            VideosView(ndk: ndk)
                .tag(MainTab.videos)
                .tabItem {
                    Label(MainTab.videos.label, systemImage: MainTab.videos.selectedIcon)
                }

            Color.clear
                .tag(MainTab.createPost)
                .tabItem {
                    Label(MainTab.createPost.label, systemImage: MainTab.createPost.icon)
                }

            ExploreView(ndk: ndk)
                .tag(MainTab.explore)
                .tabItem {
                    Label(MainTab.explore.label, systemImage: MainTab.explore.selectedIcon)
                }

            walletView
                .tag(MainTab.wallet)
                .tabItem {
                    Label(MainTab.wallet.label, systemImage: MainTab.wallet.selectedIcon)
                }
        }
    }

    @ViewBuilder
    private var walletView: some View {
        switch settings.walletType {
        case .spark:
            SparkWalletView(walletManager: sparkWalletManager)
        case .cashu:
            WalletView(ndk: ndk, walletViewModel: coordinator.walletViewModel)
        case .nwc:
            NWCWalletView(walletManager: nwcWalletManager)
        }
    }

}
