import CoreImage.CIFilterBuiltins
import NDKSwiftCore
import SwiftUI

/// View for reconnecting a NIP-46 remote signer when the session has expired
struct SignerReconnectView: View {
    let session: NDKSession
    let ndk: NDK
    let authManager: NDKAuthManager
    let onDismiss: () -> Void

    @State private var bunkerSigner: NDKBunkerSigner?
    @State private var nostrConnectURL: String?
    @State private var qrCodeImage: UIImage?
    @State private var isWaitingForConnection = false
    @State private var errorMessage: String?
    @State private var showError = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("Signer Reconnection Required")
                            .font(.title2.bold())

                        Text("Your remote signer session has expired. Scan the QR code with your signer app to reconnect.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Account info
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Account")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(formatPubkey(session.pubkey))
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // QR Code
                    if let qrImage = qrCodeImage {
                        VStack(spacing: 16) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 220, height: 220)
                                .padding()
                                .background(.white)
                                .cornerRadius(16)

                            if isWaitingForConnection {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Waiting for signer...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            // Copy URI button
                            if let url = nostrConnectURL {
                                Button {
                                    UIPasteboard.general.string = url
                                } label: {
                                    Label("Copy Connection URI", systemImage: "doc.on.doc")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    } else {
                        ProgressView("Generating QR code...")
                            .frame(height: 220)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 24)
            }
            .navigationTitle("Reconnect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
            .task {
                await generateNostrConnectQR()
            }
            .alert("Connection Error", isPresented: $showError) {
                Button("Try Again") {
                    Task { await generateNostrConnectQR() }
                }
                Button("Cancel", role: .cancel) {
                    onDismiss()
                }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
    }

    private func formatPubkey(_ pubkey: String) -> String {
        if let npub = try? Bech32.npub(from: pubkey) {
            let prefix = npub.prefix(12)
            let suffix = npub.suffix(8)
            return "\(prefix)...\(suffix)"
        }
        return "\(pubkey.prefix(12))...\(pubkey.suffix(8))"
    }

    private func generateNostrConnectQR() async {
        do {
            let relays = ["wss://relay.damus.io"]
            let localSigner = try NDKPrivateKeySigner.generate()

            let options = NDKBunkerSigner.NostrConnectOptions(
                name: "Olas",
                url: "https://olas.app",
                image: "https://olas.app/icon.png",
                perms: "sign_event:1,sign_event:7,sign_event:20,sign_event:22,sign_event:1111,nip04_encrypt,nip04_decrypt,nip44_encrypt,nip44_decrypt"
            )

            let signer = try await NDKBunkerSigner.nostrConnect(
                ndk: ndk,
                relays: relays,
                localSigner: localSigner,
                options: options
            )

            bunkerSigner = signer

            // Wait for URI to be generated
            var url: String?
            for _ in 1 ... 20 {
                url = await signer.nostrConnectUri
                if url != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }

            if let url = url {
                nostrConnectURL = url
                generateQRCode(from: url)

                // Start listening for connection
                isWaitingForConnection = true
                Task {
                    await waitForSignerConnection()
                }
            }
        } catch {
            errorMessage = "Failed to generate QR code: \(error.localizedDescription)"
            showError = true
        }
    }

    private func generateQRCode(from string: String) {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")

        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            if let cgimg = context.createCGImage(scaledImage, from: scaledImage.extent) {
                qrCodeImage = UIImage(cgImage: cgimg)
            }
        }
    }

    private func waitForSignerConnection() async {
        guard let signer = bunkerSigner else { return }

        do {
            // Wait for the signer to connect (user scans QR and approves)
            let connectedPubkey = try await signer.connect()

            // Verify the pubkey matches the session
            guard connectedPubkey == session.pubkey else {
                await MainActor.run {
                    isWaitingForConnection = false
                    errorMessage = "The signer returned a different account. Please use the correct signer for this account."
                    showError = true
                }
                return
            }

            // Update the session with the new signer
            try await authManager.updateSessionSigner(session, signer: signer)

            await MainActor.run {
                isWaitingForConnection = false
                onDismiss()
            }
        } catch {
            await MainActor.run {
                isWaitingForConnection = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
