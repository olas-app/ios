import NDKSwiftCore
import NDKSwiftNostrDB
import SwiftUI

@main
struct OlasApp: App {
    @State private var authViewModel = AuthViewModel()
    @State private var settings = SettingsManager()
    @State private var relayCache = RelayMetadataCache()
    @State private var imageCache = ImageCache()
    @State private var publishingState = PublishingState()
    @State private var ndk: NDK?
    @State private var sparkWalletManager: SparkWalletManager?
    @State private var nwcWalletManager: NWCWalletManager?
    @State private var isInitialized = false
    @State private var pendingNWCURI: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if !isInitialized {
                    ProgressView("Connecting...")
                        .task {
                            await initializeNDK()
                        }
                } else if !authViewModel.isLoggedIn {
                    OnboardingView(authViewModel: authViewModel)
                } else if let ndk = ndk, let sparkWalletManager = sparkWalletManager, let nwcWalletManager = nwcWalletManager {
                    if authViewModel.isNewAccount && !settings.hasCompletedOnboarding {
                        OnboardingFlowView(ndk: ndk) {
                            settings.hasCompletedOnboarding = true
                        }
                        .environment(authViewModel)
                        .environment(\.ndk, ndk)
                        .environment(settings)
                    } else {
                        MainTabView(ndk: ndk, sparkWalletManager: sparkWalletManager, nwcWalletManager: nwcWalletManager)
                            .environment(authViewModel)
                            .environment(\.ndk, ndk)
                            .environment(settings)
                            .environment(relayCache)
                            .environment(imageCache)
                            .environment(publishingState)
                    }
                }
            }
            .environment(settings)
            .environment(relayCache)
            .environment(imageCache)
            .onChange(of: authViewModel.isLoggedIn) { _, isLoggedIn in
                if isLoggedIn {
                    ndk?.signer = authViewModel.signer
                } else {
                    ndk?.signer = nil
                    settings.hasCompletedOnboarding = false
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
            print("[OlasApp] NIP-46 signer returned via callback")
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
            print("[OlasApp] NWC connection failed: \(error)")
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
            print("Failed to create cache directory: \(error)")
        }

        // Create cache first, then pass to NDK
        var cache: (any NDKCache)?
        do {
            cache = try await NDKNostrDBCache(path: cachePath)
            print("✓ NostrDB cache initialized at: \(cachePath)")
        } catch {
            print("❌ Failed to initialize NostrDB cache: \(error)")
            print("   Path: \(cachePath)")
            print("   Stats will be unavailable in Developer Tools")
        }

        let newNDK = NDK(relayURLs: relayUrls, cache: cache)

        // Set NDK reference in AuthViewModel before restoring session
        authViewModel.setNDK(newNDK)

        // Restore session if available
        await authViewModel.restoreSession()

        // Set signer if logged in
        if authViewModel.isLoggedIn {
            newNDK.signer = authViewModel.signer
        }

        await newNDK.connect()

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
            self.sparkWalletManager = sparkManager
            self.nwcWalletManager = nwcManager
            self.isInitialized = true
        }
    }
}
