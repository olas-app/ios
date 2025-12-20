import CoreImage.CIFilterBuiltins
import NDKSwiftCore
import SwiftUI

@MainActor
class NIP46ViewModel: ObservableObject {
    @Published var nostrConnectURL: String?
    @Published var qrCode: UIImage?
    @Published var isWaitingForConnection = false
    @Published var connectionError: Error?
    @Published var connectedUser: NDKUser?

    private var bunkerSigner: NDKBunkerSigner?
    weak var ndk: NDK?

    init(ndk: NDK?) {
        self.ndk = ndk
    }

    func generateNostrConnectURL() async {
        print("🔵 [NIP46] Starting QR code generation...")
        do {
            // 1. Create an NDK instance or use the provided one
            guard let ndk = ndk else {
                print("🔴 [NIP46] Error: NDK instance not available")
                return
            }
            print("✅ [NIP46] NDK instance available")

            // 2. Specify the relays for the remote signer to connect back to.
            let relays = ["wss://relay.damus.io"]
            print("✅ [NIP46] Using relays: \(relays)")

            // 3. Create a new local key pair for this connection.
            // This is used to encrypt communication with the remote signer.
            let localSigner = try NDKPrivateKeySigner.generate()
            print("✅ [NIP46] Generated local signer")

            // 4. Define your app's metadata.
            let options = NDKBunkerSigner.NostrConnectOptions(
                name: "Olas",
                url: "https://olas.io",
                image: "https://olas.io/favicon.ico",
                perms: "sign_event:1,nip04_encrypt,nip04_decrypt" // Request permissions
            )
            print("✅ [NIP46] Created options")

            // 5. Create the bunker signer instance.
            print("🔵 [NIP46] Creating bunker signer...")
            let bunkerSigner = try await NDKBunkerSigner.nostrConnect(
                ndk: ndk,
                relays: relays,
                localSigner: localSigner,
                options: options
            )
            print("✅ [NIP46] Bunker signer created")

            // Store the bunker signer for later use
            self.bunkerSigner = bunkerSigner

            // 6. Wait for the nostrconnect URL to be generated
            // The URI is generated asynchronously in a Task, so we need to poll for it
            print("🔵 [NIP46] Waiting for nostrConnectUri to be generated...")
            var url: String?
            for attempt in 1 ... 20 {
                url = await bunkerSigner.nostrConnectUri
                if url != nil {
                    break
                }
                print("⏳ [NIP46] Attempt \(attempt): URI not ready yet, waiting...")
                try? await Task.sleep(for: .milliseconds(100))
            }

            if let url = url {
                print("✅ [NIP46] Got nostrconnect URL: \(url)")
                nostrConnectURL = url
                generateQRCode(from: url)
                print("✅ [NIP46] QR code generated successfully")
            } else {
                print("🔴 [NIP46] Timeout: nostrConnectUri never became available!")
            }
        } catch {
            print("🔴 [NIP46] Error generating nostrconnect URL: \(error)")
            connectionError = error
        }
    }

    func waitForConnection() async throws -> (NDKBunkerSigner, PublicKey) {
        guard let bunkerSigner = bunkerSigner, let ndk = ndk else {
            throw NIP46Error.signerNotInitialized
        }

        isWaitingForConnection = true
        defer { isWaitingForConnection = false }

        // Wait for the remote signer to connect
        // The connect() method will wait for the remote signer to respond
        let pubkey = try await bunkerSigner.connect()
        connectedUser = try await NDKUser(pubkey: pubkey, ndk: ndk)

        return (bunkerSigner, pubkey)
    }

    private func generateQRCode(from string: String) {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(string.utf8)

        filter.setValue(data, forKey: "inputMessage")

        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            if let cgimg = context.createCGImage(scaledImage, from: scaledImage.extent) {
                qrCode = UIImage(cgImage: cgimg)
            }
        }
    }

    // Method to get the bunker signer once connection is established
    func getBunkerSigner() -> NDKBunkerSigner? {
        return bunkerSigner
    }
}

enum NIP46Error: LocalizedError {
    case signerNotInitialized

    var errorDescription: String? {
        switch self {
        case .signerNotInitialized:
            return "Signer not initialized. Please generate QR code first."
        }
    }
}
