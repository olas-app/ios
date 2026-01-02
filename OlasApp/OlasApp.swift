import NDKSwiftCore
import NDKSwiftNostrDB
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

    // DEBUG: Visible debug state
    @State private var debugMessage: String = ""
    @State private var showDebugAlert = false

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
            .alert("Session Debug", isPresented: $showDebugAlert) {
                Button("OK") {}
            } message: {
                Text(debugMessage)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
            logInfo("NIP-46 signer returned via callback", category: "App")
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
        } catch {
            logError("NWC connection failed: \(error.localizedDescription)", category: "NWC")
        }
    }

    private func initializeNDK() async {
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
        } catch {
            logError("Failed to create cache directory: \(error.localizedDescription)", category: "Cache")
        }

        // Create cache first, then pass to NDK
        var cache: (any NDKCache)?
        do {
            cache = try await NDKNostrDBCache(path: cachePath)
            logInfo("NostrDB cache initialized", category: "Cache", metadata: ["path": cachePath])
        } catch {
            logError("Failed to initialize NostrDB cache: \(error.localizedDescription)", category: "Cache", metadata: ["path": cachePath])
        }

        let newNDK = NDK(relayURLs: relayUrls, cache: cache)

        // Create auth manager with NDK
        let newAuthManager = NDKAuthManager(ndk: newNDK)

        // DEBUG: Check keychain BEFORE initialize (which might delete sessions)
        let keychainManagerPre = NDKKeychainManager()
        var preInitIds: [String] = []
        do {
            preInitIds = try await keychainManagerPre.getAllSessionIdentifiers()
        } catch {
            preInitIds = ["ERROR: \(error)"]
        }
        UserDefaults.standard.set("PRE-INIT: \(preInitIds.count) IDs", forKey: "NDK_DEBUG_PRE_INIT")

        // Restore session - NDKAuthManager automatically sets signer on NDK
        await newAuthManager.initialize()

        // DEBUG: Check keychain AFTER initialize
        let keychainManager = NDKKeychainManager()
        var keychainSessionIds: [String] = []
        do {
            keychainSessionIds = try await keychainManager.getAllSessionIdentifiers()
        } catch {
            keychainSessionIds = ["ERROR: \(error.localizedDescription)"]
        }

        // DEBUG: Read debug info from UserDefaults
        let restoreStatus = UserDefaults.standard.string(forKey: "NDK_DEBUG_RESTORE") ?? "no restore"
        let rawSigner = UserDefaults.standard.string(forKey: "NDK_DEBUG_RAW_SIGNER") ?? "no raw data"

        // DEBUG: Capture session state for debugging
        let sessionCount = newAuthManager.availableSessions.count
        let isAuth = newAuthManager.isAuthenticated
        let debugInfo = "Restore: \(restoreStatus)\n\n\(rawSigner)\n\nSessions: \(sessionCount), Auth: \(isAuth)"
        await MainActor.run {
            self.debugMessage = debugInfo
            self.showDebugAlert = true
        }

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
            self.ndk = newNDK
            self.authManager = newAuthManager
            self.sparkWalletManager = sparkManager
            self.nwcWalletManager = nwcManager
            self.followPackManager = packManager
            self.isInitialized = true
        }
    }
}
