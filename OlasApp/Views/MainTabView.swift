// MainTabView.swift
import NDKSwiftCore
import SwiftUI

// MARK: - Tab Bar State Manager
@Observable
public final class TabBarState {
    public var isMinimized: Bool = false
    private var previousOffset: CGFloat = 0
    private var accumulatedDelta: CGFloat = 0
    private let minimizeThreshold: CGFloat = 100  // Scroll down this much to minimize
    private let expandThreshold: CGFloat = 50     // Scroll up this much to expand

    public func updateScrollOffset(_ offset: CGFloat) {
        let delta = offset - previousOffset
        previousOffset = offset

        // Accumulate delta in the current direction
        if delta > 0 {
            // Scrolling down
            if accumulatedDelta < 0 {
                accumulatedDelta = 0  // Reset when direction changes
            }
            accumulatedDelta += delta

            if accumulatedDelta > minimizeThreshold && !isMinimized {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isMinimized = true
                }
                accumulatedDelta = 0
            }
        } else if delta < 0 {
            // Scrolling up
            if accumulatedDelta > 0 {
                accumulatedDelta = 0  // Reset when direction changes
            }
            accumulatedDelta += delta

            if accumulatedDelta < -expandThreshold && isMinimized {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isMinimized = false
                }
                accumulatedDelta = 0
            }
        }
    }

    public func resetScroll() {
        previousOffset = 0
        accumulatedDelta = 0
    }
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

public struct MainTabView: View {
    @Environment(NDKAuthManager.self) private var authManager
    @State private var walletViewModel: WalletViewModel
    @State private var muteListManager: MuteListManager
    @Environment(SettingsManager.self) private var settings
    @Environment(PublishingState.self) private var publishingState
    @State private var selectedTab = 0
    @State private var showCreatePost = false
    @State private var tabBarState = TabBarState()

    private let ndk: NDK
    private var sparkWalletManager: SparkWalletManager
    private var nwcWalletManager: NWCWalletManager

    // Tab configuration
    private let tabs: [(icon: String, selectedIcon: String, label: String)] = [
        ("wave.3.up.circle", "wave.3.up.circle.fill", "Home"),
        ("play.circle", "play.circle.fill", "Videos"),
        ("magnifyingglass.circle", "magnifyingglass.circle.fill", "Explore"),
        ("creditcard", "creditcard.fill", "Wallet")
    ]

    public init(ndk: NDK, sparkWalletManager: SparkWalletManager, nwcWalletManager: NWCWalletManager) {
        self.ndk = ndk
        self._walletViewModel = State(initialValue: WalletViewModel(ndk: ndk))
        self._muteListManager = State(initialValue: MuteListManager(ndk: ndk))
        self.sparkWalletManager = sparkWalletManager
        self.nwcWalletManager = nwcWalletManager
    }

    // MARK: - Liquid Glass Navigation Constants
    private let buttonSize: CGFloat = 44
    private let dockPadding: CGFloat = 6
    private let iconSize: CGFloat = 22

    // Computed dock width for smooth animation
    private var expandedDockWidth: CGFloat {
        CGFloat(tabs.count) * buttonSize + CGFloat(tabs.count - 1) * 8 + dockPadding * 2
    }

    private var minimizedDockWidth: CGFloat {
        buttonSize + dockPadding * 2
    }

    // MARK: - Liquid Navigation Dock
    @ViewBuilder
    private var liquidNavigationDock: some View {
        // Container that smoothly animates width
        HStack(spacing: 8) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                let isActive = selectedTab == index
                let shouldShow = !tabBarState.isMinimized || isActive

                TabBarButton(
                    icon: tab.icon,
                    selectedIcon: tab.selectedIcon,
                    label: tab.label,
                    isSelected: isActive
                ) {
                    if tabBarState.isMinimized {
                        // Tap on minimized dot expands the dock
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            tabBarState.isMinimized = false
                        }
                    } else {
                        selectedTab = index
                    }
                }
                .frame(width: shouldShow ? buttonSize : 0, height: buttonSize)
                .opacity(shouldShow ? 1 : 0)
                .scaleEffect(shouldShow ? 1 : 0.5)
            }
        }
        .padding(dockPadding)
        .frame(width: tabBarState.isMinimized ? minimizedDockWidth : expandedDockWidth)
        .glassEffect(.regular.interactive())
        .clipShape(Capsule())
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tabBarState.isMinimized)
    }

    // MARK: - Action Satellite Button
    @ViewBuilder
    private var actionSatellite: some View {
        Button {
            showCreatePost = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: iconSize, weight: .bold))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
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

            // Custom dual-pill bottom bar - Liquid Glass design
            HStack(spacing: 12) {
                // Main navigation dock - smoothly animates between expanded and minimized
                liquidNavigationDock

                // Action satellite - perfect circle '+' button
                actionSatellite
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .tint(.primary)
        .environment(tabBarState)
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

    // Button size constants for Liquid Glass aesthetic
    private let buttonSize: CGFloat = 44
    private let iconSize: CGFloat = 22

    var body: some View {
        Button(action: action) {
            ZStack {
                // Circular active background - high contrast indicator
                Circle()
                    .fill(Color.primary.opacity(isSelected ? 0.15 : 0))
                    .frame(width: buttonSize, height: buttonSize)

                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: iconSize, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
