import NDKSwiftCore
import SwiftUI

public struct MainTabView: View {
    @Environment(NDKAuthManager.self) private var authManager
    @Environment(SettingsManager.self) private var settings
    @Environment(PublishingState.self) private var publishingState

    @State private var coordinator: MainTabCoordinator
    @State private var selectedTab: MainTab = .home
    @State private var showCreatePost = false
    @State private var tabBarState = TabBarState()

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
        ZStack(alignment: .bottom) {
            tabContent
            bottomBar
        }
        .tint(.primary)
        .environment(tabBarState)
        .fullScreenCover(isPresented: $showCreatePost) {
            CreatePostView(ndk: ndk)
        }
        .task {
            await coordinator.performSetup(
                userPubkey: authManager.activePubkey,
                muteListSources: settings.muteListSources
            )
        }
        .onChange(of: settings.muteListSources) { _, newSources in
            coordinator.updateMuteListSources(newSources)
        }
        .environment(coordinator.walletViewModel)
        .environment(coordinator.muteListManager)
        .environment(sparkWalletManager)
        .environment(nwcWalletManager)
        .overlay(alignment: .top) {
            PublishingBannerOverlay(publishingState: publishingState)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            FeedView(ndk: ndk, settings: settings)
        case .videos:
            VideosView(ndk: ndk)
        case .explore:
            ExploreView(ndk: ndk)
        case .wallet:
            walletView
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

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: 12) {
            LiquidNavigationDock(
                selectedTab: $selectedTab,
                tabBarState: tabBarState
            )
            ActionSatelliteButton(accessibilityLabel: "Create post") {
                showCreatePost = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}
