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
        TabView(selection: $selectedTab) {
            FeedView(ndk: ndk, settings: settings)
                .tabItem {
                    Label("Home", systemImage: selectedTab == 0 ? "wave.3.up.circle.fill" : "wave.3.up.circle")
                }
                .tag(0)

            ExploreView(ndk: ndk)
                .tabItem {
                    Label("Explore", systemImage: selectedTab == 1 ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                }
                .tag(1)

            // Create - triggers sheet
            Color.clear
                .tabItem {
                    Label("", systemImage: "plus.app.fill")
                }
                .tag(2)

            // Wallet - show Spark, Cashu, or NWC based on settings
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
            .tabItem {
                Label("Wallet", systemImage: selectedTab == 3 ? "creditcard.fill" : "creditcard")
            }
            .tag(3)

            // Profile
            NavigationStack {
                if let pubkey = authManager.activePubkey {
                    ProfileView(ndk: ndk, pubkey: pubkey, currentUserPubkey: pubkey, sparkWalletManager: sparkWalletManager, nwcWalletManager: nwcWalletManager)
                } else {
                    Text("Not logged in")
                }
            }
            .tabItem {
                Label("Profile", systemImage: selectedTab == 4 ? "person.fill" : "person")
            }
            .tag(4)
        }
        .tint(.primary)
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 2 {
                showCreatePost = true
                selectedTab = oldValue
            }
        }
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
                                .foregroundStyle(.white)
                        }

                        Text(publishingState.publishingStatus)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)

                        Spacer()

                        if publishingState.error != nil {
                            Button {
                                publishingState.dismissError()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }

                    // Progress bar
                    if publishingState.error == nil {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background track
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.3))
                                    .frame(height: 4)

                                // Progress fill
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white)
                                    .frame(width: geometry.size.width * publishingState.publishingProgress, height: 4)
                                    .animation(.easeOut(duration: 0.2), value: publishingState.publishingProgress)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.9))
                        .shadow(radius: 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: publishingState.isPublishing)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: publishingState.error != nil)
            }
        }
    }
}
