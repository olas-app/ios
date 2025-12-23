import CoreImage.CIFilterBuiltins
import NDKSwiftCore
import SwiftUI

@Observable @MainActor
final class NIP46ViewModel {
    var nostrConnectURL: String?
    var qrCode: UIImage?
    var isWaitingForConnection = false
    var connectionError: Error?
    var connectedUser: NDKUser?

    private var bunkerSigner: NDKBunkerSigner?
    weak var ndk: NDK?

    init(ndk: NDK?) {
        self.ndk = ndk
    }

    func generateNostrConnectURL() async {
        Log.debug("Starting QR code generation", category: "NIP46")
        do {
            guard let ndk = ndk else {
                Log.error("NDK instance not available", category: "NIP46")
                return
            }
            Log.debug("NDK instance available", category: "NIP46")

            let relays = ["wss://relay.damus.io"]
            Log.debug("Using relays: \(relays)", category: "NIP46")

            let localSigner = try NDKPrivateKeySigner.generate()
            Log.debug("Generated local signer", category: "NIP46")

            let options = NDKBunkerSigner.NostrConnectOptions(
                name: "Olas",
                url: "https://olas.io",
                image: "https://olas.io/favicon.ico",
                perms: "sign_event:1,nip04_encrypt,nip04_decrypt"
            )
            Log.debug("Created options", category: "NIP46")

            Log.debug("Creating bunker signer", category: "NIP46")
            let bunkerSigner = try await NDKBunkerSigner.nostrConnect(
                ndk: ndk,
                relays: relays,
                localSigner: localSigner,
                options: options
            )
            Log.info("Bunker signer created", category: "NIP46")

            self.bunkerSigner = bunkerSigner

            Log.debug("Waiting for nostrConnectUri to be generated", category: "NIP46")
            var url: String?
            for attempt in 1 ... 20 {
                url = await bunkerSigner.nostrConnectUri
                if url != nil {
                    break
                }
                Log.debug("Attempt \(attempt): URI not ready yet", category: "NIP46")
                try? await Task.sleep(for: .milliseconds(100))
            }

            if let url = url {
                Log.info("Got nostrconnect URL", category: "NIP46", metadata: ["url": String(url.prefix(50))])
                nostrConnectURL = url
                generateQRCode(from: url)
                Log.info("QR code generated successfully", category: "NIP46")
            } else {
                Log.error("Timeout: nostrConnectUri never became available", category: "NIP46")
            }
        } catch {
            Log.error("Error generating nostrconnect URL: \(error.localizedDescription)", category: "NIP46")
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
