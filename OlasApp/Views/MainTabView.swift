// MainTabView.swift
import NDKSwiftCore
import SwiftUI

public struct MainTabView: View {
    @Environment(NDKAuthManager.self) private var authManager
    @State private var walletViewModel: WalletViewModel
    @State private var muteListManager: MuteListManager
    @Environment(SettingsManager.self) private var settings
    @Environment(PublishingState.self) private var publishingState
    @State private var selectedTab = 0
    @State private var showCreatePost = false

    private let ndk: NDK
    private var sparkWalletManager: SparkWalletManager
    private var nwcWalletManager: NWCWalletManager

    public init(ndk: NDK, sparkWalletManager: SparkWalletManager, nwcWalletManager: NWCWalletManager) {
        self.ndk = ndk
        self._walletViewModel = State(initialValue: WalletViewModel(ndk: ndk))
        self._muteListManager = State(initialValue: MuteListManager(ndk: ndk))
        self.sparkWalletManager = sparkWalletManager
        self.nwcWalletManager = nwcWalletManager
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Content area - switch between views based on selected tab
            Group {
                switch selectedTab {
                case 0:
                    FeedView(ndk: ndk, settings: settings)
                case 1:
                    VideosView(ndk: ndk)
                case 2:
                    ExploreView(ndk: ndk)
                case 3:
                    Group {
                        switch settings.walletType {
                        case .spark:
                            SparkWalletView(walletManager: sparkWalletManager)
                        case .cashu:
                            WalletView(ndk: ndk, walletViewModel: walletViewModel)
                        case .nwc:
                            NWCWalletView(walletManager: nwcWalletManager)
                        }
                    }
                default:
                    FeedView(ndk: ndk, settings: settings)
                }
            }

            // Custom dual-pill bottom bar
            HStack(spacing: 12) {
                // Main navigation pill
                HStack(spacing: 0) {
                    TabBarButton(
                        icon: "wave.3.up.circle",
                        selectedIcon: "wave.3.up.circle.fill",
                        label: "Home",
                        isSelected: selectedTab == 0
                    ) {
                        selectedTab = 0
                    }

                    TabBarButton(
                        icon: "play.circle",
                        selectedIcon: "play.circle.fill",
                        label: "Videos",
                        isSelected: selectedTab == 1
                    ) {
                        selectedTab = 1
                    }

                    TabBarButton(
                        icon: "magnifyingglass.circle",
                        selectedIcon: "magnifyingglass.circle.fill",
                        label: "Explore",
                        isSelected: selectedTab == 2
                    ) {
                        selectedTab = 2
                    }

                    TabBarButton(
                        icon: "creditcard",
                        selectedIcon: "creditcard.fill",
                        label: "Wallet",
                        isSelected: selectedTab == 3
                    ) {
                        selectedTab = 3
                    }
                }
                .glassEffect(.regular.interactive())

                // Create button pill
                Button {
                    showCreatePost = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 50, height: 50)
                }
                .glassEffect(.regular.interactive())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .tint(.primary)
        .fullScreenCover(isPresented: $showCreatePost) {
            CreatePostView(ndk: ndk)
        }
        .task {
            await walletViewModel.loadWallet()
            // Initialize mute list sources from settings and start subscription
            muteListManager.userPubkey = authManager.activePubkey
            muteListManager.updateMuteListSources(settings.muteListSources)
            muteListManager.startSubscription()
        }
        .onChange(of: settings.muteListSources) { _, newSources in
            // Sync mute list manager when settings change
            muteListManager.updateMuteListSources(newSources)
        }
        .environment(walletViewModel)
        .environment(muteListManager)
        .environment(sparkWalletManager)
        .environment(nwcWalletManager)
        .overlay(alignment: .top) {
            if publishingState.isPublishing || publishingState.error != nil {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        if publishingState.error != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(.tint)
                        }

                        Text(publishingState.publishingStatus)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        if publishingState.error != nil {
                            Button {
                                publishingState.dismissError()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Progress bar
                    if publishingState.error == nil {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background track
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.primary.opacity(0.2))
                                    .frame(height: 4)

                                // Progress fill
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor)
                                    .frame(width: geometry.size.width * publishingState.publishingProgress, height: 4)
                                    .animation(.easeOut(duration: 0.2), value: publishingState.publishingProgress)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect()
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: publishingState.isPublishing)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: publishingState.error != nil)
            }
        }
    }
}

// MARK: - Tab Bar Button Component
private struct TabBarButton: View {
    let icon: String
    let selectedIcon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 24))
                Text(label)
                    .font(.caption2)
            }
            .frame(width: 70, height: 50)
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}
