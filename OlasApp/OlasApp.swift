import NDKSwiftCore
import NDKSwiftNostrDB
import SwiftUI

@main
struct OlasApp: App {
    @State private var settings = SettingsManager()
    @State private var relayCache = RelayMetadataCache()
    @State private var imageCache = ImageCache()
    @State private var publishingState = PublishingState()
    @State private var ndk: NDK?
    @State private var authManager: NDKAuthManager?
    @State private var sparkWalletManager: SparkWalletManager?
    @State private var nwcWalletManager: NWCWalletManager?
    @State private var isInitialized = false
    @State private var pendingNWCURI: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if !isInitialized {
                    ProgressView("Loading...")
                        .task {
                            await initializeNDK()
                        }
                } else if let authManager = authManager, let ndk = ndk {
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
                        } else {
                            MainTabView(ndk: ndk, sparkWalletManager: sparkWalletManager, nwcWalletManager: nwcWalletManager)
                                .environment(authManager)
                                .environment(\.ndk, ndk)
                                .environment(settings)
                                .environment(relayCache)
                                .environment(imageCache)
                                .environment(publishingState)
                        }
                    }
                }
            }
            .environment(settings)
            .environment(relayCache)
            .environment(imageCache)
            .onChange(of: authManager?.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated != true {
                    settings.hasCompletedOnboarding = false
                    settings.isNewAccount = false
                }
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
        }
    }

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

        // Restore session - NDKAuthManager automatically sets signer on NDK
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

        await MainActor.run {
            self.ndk = newNDK
            self.authManager = newAuthManager
            self.sparkWalletManager = sparkManager
            self.nwcWalletManager = nwcManager
            self.isInitialized = true
        }
    }
}
