// MainTabView.swift
import SwiftUI
import NDKSwiftCore

public struct MainTabView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var walletViewModel: WalletViewModel
    @StateObject private var muteListManager: MuteListManager
    @Environment(SettingsManager.self) private var settings
    @Environment(PostManager.self) private var postManager
    @State private var selectedTab = 0
    @State private var showCreatePost = false

    private let ndk: NDK
    private var sparkWalletManager: SparkWalletManager

    public init(ndk: NDK, sparkWalletManager: SparkWalletManager) {
        self.ndk = ndk
        self._walletViewModel = StateObject(wrappedValue: WalletViewModel(ndk: ndk))
        self._muteListManager = StateObject(wrappedValue: MuteListManager(ndk: ndk))
        self.sparkWalletManager = sparkWalletManager
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

            // Wallet - show Spark or Cashu based on settings
            Group {
                switch settings.walletType {
                case .spark:
                    SparkWalletView(walletManager: sparkWalletManager)
                case .cashu:
                    WalletView(ndk: ndk, walletViewModel: walletViewModel)
                }
            }
            .tabItem {
                Label("Wallet", systemImage: selectedTab == 3 ? "creditcard.fill" : "creditcard")
            }
            .tag(3)

            // Profile
            NavigationStack {
                if let pubkey = authViewModel.currentUser?.pubkey {
                    ProfileView(ndk: ndk, pubkey: pubkey, currentUserPubkey: pubkey, sparkWalletManager: sparkWalletManager)
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
            muteListManager.startSubscription()
        }
        .environmentObject(walletViewModel)
        .environmentObject(muteListManager)
        .environment(sparkWalletManager)
        .overlay(alignment: .top) {
            if postManager.isPublishing || postManager.error != nil {
                HStack(spacing: 12) {
                    if postManager.error != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } else {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(postManager.publishingStatus)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)

                    Spacer()

                    if postManager.error != nil {
                        Button {
                            postManager.dismissError()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    Capsule()
                        .fill(Color.black.opacity(0.9))
                        .shadow(radius: 4)
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: postManager.isPublishing)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: postManager.error != nil)
            }
        }
    }
}
