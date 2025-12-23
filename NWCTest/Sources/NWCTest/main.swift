import Foundation
import NDKSwiftCore

let nwcURI = "nostr+walletconnect://1291af9c119879ef7a59636432c6e06a7a058c0cae80db27c0f20f61f3734e52?relay=wss%3A%2F%2Fnwc.primal.net%2Fgx0168jvz6xcaehqu3uiq7j3dywelc&secret=edd9b22a1cca14107910c6e348566bd4deb421a42eba24cb540c3fd73d1c8b17&lud16=pablof7z%40primal.net"

@main
struct NWCTest {
    static func main() async throws {
        // Force stdout to be unbuffered
        setbuf(stdout, nil)

        print("🔍 NWC Full Protocol Test using NDKSwift")
        print(String(repeating: "=", count: 50))

        NDKLogger.configure(logLevel: .trace, logNetworkTraffic: true)

        print("\n📡 Creating NDK instance...")
        let ndk = NDK(relayURLs: [])

        print("📡 Calling ndk.connect()...")
        await ndk.connect()
        print("✅ ndk.connect() completed")

        print("\n🔑 Creating NWC wallet from URI...")
        let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: nwcURI)
        print("✅ Wallet created! Pubkey: \(wallet.connectionURI.walletPubkey)")

        print("\n🔗 Connecting to wallet...")
        try await wallet.connect()
        print("✅ Connected!")

        print("\n💰 Getting balance...")
        if let balance = try await wallet.getBalance() {
            print("✅ Balance: \(balance) sats")
        }

        print("\n✅ NWC TEST PASSED!")
    }
}
