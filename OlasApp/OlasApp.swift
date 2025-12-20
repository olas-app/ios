import NDKSwiftCore
import NDKSwiftNostrDB
import SwiftUI

@main
struct OlasApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @State private var settings = SettingsManager()
    @State private var relayCache = RelayMetadataCache()
    @State private var imageCache = ImageCache()
    @State private var publishingState = PublishingState()
    @State private var ndk: NDK?
    @State private var sparkWalletManager: SparkWalletManager?
    @State private var isInitialized = false

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
                } else if let ndk = ndk, let sparkWalletManager = sparkWalletManager {
                    MainTabView(ndk: ndk, sparkWalletManager: sparkWalletManager)
                        .environmentObject(authViewModel)
                        .environment(\.ndk, ndk)
                        .environment(settings)
                        .environment(relayCache)
                        .environment(imageCache)
                        .environment(publishingState)
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
                }
            }
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
        let walletManager = SparkWalletManager()

        // Attempt to restore saved wallet
        await walletManager.restoreWalletIfExists()

        await MainActor.run {
            self.ndk = newNDK
            self.sparkWalletManager = walletManager
            self.isInitialized = true
        }
    }
}
