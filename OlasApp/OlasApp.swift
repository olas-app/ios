import Combine
import NDKSwiftCore
import SwiftUI

@main
struct OlasApp: App {
    @State private var settings = SettingsManager()
    @State private var relayCache = RelayMetadataCache()
    @State private var publishingState = PublishingState()
    @State private var feedSourcesManager = SavedFeedSourcesManager()
    @State private var ndk: NDK?
    @State private var authManager: NDKAuthManager?
    @State private var sparkWalletManager: SparkWalletManager?
    @State private var nwcWalletManager: NWCWalletManager?
    @State private var followPackManager: FollowPackManager?
    @State private var isInitialized = false
    @State private var pendingNWCURI: String?

    // Signing failure UI state
    @State private var showSigningError = false
    @State private var signingErrorMessage = ""

    // Session validation failure UI state (use item binding to guarantee session is present)
    @State private var invalidSession: NDKSession?

    // Splash screen animation state
    @State private var logoScale: CGFloat = 0.3
    @State private var logoOpacity: CGFloat = 0
    @State private var splashBackgroundOpacity: CGFloat = 1.0

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Content layer (always rendered behind splash)
                contentView

                // Splash overlay
                splashView
                    .opacity(splashBackgroundOpacity)
                    .allowsHitTesting(splashBackgroundOpacity > 0)
            }
            .environment(settings)
            .environment(relayCache)
            .onChange(of: authManager?.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated != true {
                    settings.hasCompletedOnboarding = false
                    settings.isNewAccount = false
                }
            }
            .onChange(of: authManager?.activePubkey) { _, newPubkey in
                followPackManager?.setUser(newPubkey)
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
.onChange(of: isInitialized) { _, initialized in
                if initialized, let uri = pendingNWCURI {
                    Task {
                        await connectPendingNWC(uri: uri)
                    }
                    pendingNWCURI = nil
                }
            }
            .onChange(of: authManager?.lastValidationFailure?.session.id) { _, newValue in
                // When session validation fails, show reconnect sheet
                if newValue != nil, let failure = authManager?.lastValidationFailure {
                    invalidSession = failure.session
                }
            }
            .onChange(of: ndk?.lastSigningFailure?.error.localizedDescription) { _, newValue in
                // When signing fails, show error alert
                if let failure = ndk?.lastSigningFailure {
                    signingErrorMessage = failure.error.localizedDescription
                    showSigningError = true
                    ndk?.clearSigningFailure()
                }
            }
            .alert("Action Failed", isPresented: $showSigningError) {
                Button("OK", role: .cancel) {}
                if authManager?.activeSigner is NDKBunkerSigner {
                    Button("Reconnect Signer") {
                        invalidSession = authManager?.activeSession
                    }
                }
            } message: {
                Text(signingErrorMessage)
            }
            .sheet(item: $invalidSession, onDismiss: {
                authManager?.clearValidationFailure()
                invalidSession = nil
            }) { session in
                if let ndk = ndk, let authManager = authManager {
                    LoginView(authManager: authManager, ndk: ndk, reconnectSession: session) {
                        authManager.clearValidationFailure()
                        invalidSession = nil
                    }
                }
            }
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        Group {
            if let authManager = authManager, let ndk = ndk {
                if !authManager.isAuthenticated {
                    OnboardingView(authManager: authManager, ndk: ndk, settings: settings)
                } else if let sparkWalletManager = sparkWalletManager, let nwcWalletManager = nwcWalletManager {
                    if settings.isNewAccount && !settings.hasCompletedOnboarding {
                        OnboardingFlowView(ndk: ndk) {
                            settings.hasCompletedOnboarding = true
                            settings.isNewAccount = false
                        }
                        .environment(authManager)
                        .environment(\.ndk, ndk)
                        .environment(settings)
                    } else if let followPackManager = followPackManager {
                        MainTabView(ndk: ndk, sparkWalletManager: sparkWalletManager, nwcWalletManager: nwcWalletManager)
                            .environment(authManager)
                            .environment(\.ndk, ndk)
                            .environment(settings)
                            .environment(relayCache)
                            .environment(publishingState)
                            .environment(feedSourcesManager)
                            .environment(followPackManager)
                    }
                }
            } else {
                Color(.systemBackground).ignoresSafeArea()
            }
        }
        .task {
            await initializeNDK()
        }
    }

    // MARK: - Splash View

    private var splashView: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            Image("OlasLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            startSplashAnimation()
        }
    }

    private func startSplashAnimation() {
        // Phase 1: Logo springs into view
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }

        // Phase 2: Logo zooms toward user while splash fades
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeOut(duration: 0.3)) {
                logoScale = 12.0
                logoOpacity = 0
                splashBackgroundOpacity = 0
            }
        }
    }

    // MARK: - URL Handling

private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "olas" else { return }

        switch url.host {
        case "nwc":
            handleNWCCallback(url)
        case "nip46":
            // NIP-46 callback - signer app returned to Olas
            // The actual connection is handled via relays in LoginView.waitForSignerConnection()
            // This callback just brings Olas back to foreground
            break
        default:
            break
        }
    }

    private func handleNWCCallback(_ url: URL) {
        // Handle NWC callback: olas://nwc?value=nostr+walletconnect://...
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let valueParam = components.queryItems?.first(where: { $0.name == "value" })?.value,
              let decodedURI = valueParam.removingPercentEncoding
        else {
            return
        }

        // Validate it's a proper NWC URI
        guard decodedURI.hasPrefix("nostr+walletconnect://") else {
            return
        }

        if isInitialized, let manager = nwcWalletManager {
            Task {
                await connectWithNWC(manager: manager, uri: decodedURI)
            }
        } else {
            // Store for processing after initialization
            pendingNWCURI = decodedURI
        }
    }

    private func connectPendingNWC(uri: String) async {
        guard let manager = nwcWalletManager else { return }
        await connectWithNWC(manager: manager, uri: uri)
    }

    private func connectWithNWC(manager: NWCWalletManager, uri: String) async {
        do {
            try await manager.connect(walletConnectURI: uri)
            settings.walletType = .nwc
        } catch {}
    }

    private func initializeNDK() async {
        // Prevent double initialization - LMDB cannot handle multiple opens
        guard !isInitialized && ndk == nil else { return }

        NDKLogger.configure(logLevel: .trace, logNetworkTraffic: true)

        let relayUrls = OlasConstants.defaultRelays

        // Initialize NostrDB cache
        let cachePath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("olas_cache")
            .path

        // Ensure cache directory exists
        do {
            try FileManager.default.createDirectory(
                atPath: cachePath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {}

        // Create cache, then pass to NDK
        let cache = try! await NDKNostrDBCache(path: cachePath)

        let newNDK = NDK(relayURLs: relayUrls, cache: cache)

        // Create auth manager with NDK
        let newAuthManager = NDKAuthManager(ndk: newNDK)

        // Set ndk and authManager IMMEDIATELY so onReceive can work
        // (background validation can fire before other initialization completes)
        await MainActor.run {
            self.ndk = newNDK
            self.authManager = newAuthManager
        }

        await newAuthManager.initialize()

        // Connect in background - don't block UI for network
        Task {
            await newNDK.connect()
        }

        // Initialize SparkWalletManager
        let sparkManager = SparkWalletManager()

        // Attempt to restore saved wallet
        await sparkManager.restoreWalletIfExists()

        // Initialize NWCWalletManager
        let nwcManager = NWCWalletManager(ndk: newNDK)

        // Attempt to restore NWC connection
        await nwcManager.restoreConnectionIfExists()

        // Initialize FollowPackManager
        let packManager = FollowPackManager(ndk: newNDK)
        if let userPubkey = newAuthManager.activePubkey {
            packManager.setUser(userPubkey)
        }

        await MainActor.run {
            self.sparkWalletManager = sparkManager
            self.nwcWalletManager = nwcManager
            self.followPackManager = packManager
            self.isInitialized = true
        }
    }
}
