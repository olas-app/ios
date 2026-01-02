import CoreImage.CIFilterBuiltins
import NDKSwiftCore
import SwiftUI

public struct LoginView: View {
    var authManager: NDKAuthManager
    var ndk: NDK
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var nostrConnectURL: String?
    @State private var qrCodeImage: UIImage?
    @State private var bunkerSigner: NDKBunkerSigner?
    @State private var isWaitingForConnection = false
    @State private var isLoading = false
    @State private var inputText = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var detectedSigner: KnownSigner?
    @State private var showDebugSuccess = false
    @State private var debugSuccessMessage = ""

    enum KnownSigner: CaseIterable {
        case amber
        case primal
        case other

        var name: String {
            switch self {
            case .amber: return "Amber"
            case .primal: return "Primal"
            case .other: return "Signer App"
            }
        }

        var urlScheme: String {
            switch self {
            case .amber: return "nostrsigner"
            case .primal: return "primal"
            case .other: return "nostrconnect"
            }
        }

        var icon: String {
            switch self {
            case .amber: return "key.fill"
            case .primal: return "bolt.fill"
            case .other: return "arrow.up.forward.app"
            }
        }
    }

    public init(authManager: NDKAuthManager, ndk: NDK) {
        self.authManager = authManager
        self.ndk = ndk
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // QR Code - hero element
                qrCodeSection
                    .frame(maxHeight: .infinity)

                // Bottom section
                VStack(spacing: 16) {
                    // Signer app button (only if detected)
                    if let signer = detectedSigner, let url = nostrConnectURL {
                        signerButton(signer: signer, connectURL: url)
                    }

                    // Input field
                    inputSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("Connection Failed", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .alert("Session Added", isPresented: $showDebugSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(debugSuccessMessage)
            }
        }
        .task {
            detectSignerApps()
            await generateNostrConnectQR()
        }
    }

    // MARK: - QR Code Section

    private var qrCodeSection: some View {
        VStack(spacing: 20) {
            Spacer()

            if let qrCode = qrCodeImage {
                Image(uiImage: qrCode)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(24)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 32)
                    .onTapGesture {
                        if let urlString = nostrConnectURL, let url = URL(string: urlString) {
                            openURL(url)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.secondarySystemBackground))
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.horizontal, 32)
                    .overlay {
                        ProgressView()
                    }
            }

            VStack(spacing: 4) {
                Text("Scan with your Nostr signer")
                    .font(.subheadline.weight(.medium))

                if isWaitingForConnection {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Waiting for connection...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Signer Button

    private func signerButton(signer: KnownSigner, connectURL: String) -> some View {
        Button {
            openSignerApp(connectURL: connectURL)
        } label: {
            HStack(spacing: 12) {
                if signer == .primal {
                    Image("PrimalLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: signer.icon)
                        .font(.title3)
                }

                Text("Open in \(signer.name)")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(16)
            .background(OlasTheme.Colors.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TextField("nsec or bunker://", text: $inputText)
                    .font(.system(.subheadline, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    if let clipboard = UIPasteboard.general.string {
                        inputText = clipboard
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if !inputText.isEmpty {
                Button {
                    Task { await connectWithInput() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        Text("Connect")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .background(OlasTheme.Colors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(isLoading)
            }
        }
    }

    // MARK: - Actions

    private func detectSignerApps() {
        // Check for known signer apps first (most specific to least)
        for signer in KnownSigner.allCases {
            if let url = URL(string: "\(signer.urlScheme)://"),
               UIApplication.shared.canOpenURL(url)
            {
                detectedSigner = signer
                return
            }
        }
    }

    private func openSignerApp(connectURL: String) {
        if let url = URL(string: connectURL) {
            openURL(url)
        }
    }

    private func generateNostrConnectQR() async {
        do {
            let relays = ["wss://relay.damus.io"]
            let localSigner = try NDKPrivateKeySigner.generate()

            let options = NDKBunkerSigner.NostrConnectOptions(
                name: "Olas",
                url: "https://olas.app",
                image: "https://olas.app/icon.png",
                perms: "sign_event:1,sign_event:7,sign_event:20,sign_event:22,sign_event:1111,nip04_encrypt,nip04_decrypt"
            )

            let signer = try await NDKBunkerSigner.nostrConnect(
                ndk: ndk,
                relays: relays,
                localSigner: localSigner,
                options: options
            )

            bunkerSigner = signer

            var url: String?
            for _ in 1 ... 20 {
                url = await signer.nostrConnectUri
                if url != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }

            if var url = url {
                // Add callback for signers that support return-to-app flow
                let callback = "olas://nip46"
                // Use alphanumerics to ensure :// gets encoded as %3A%2F%2F
                if let encodedCallback = callback.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
                    url += "&callback=\(encodedCallback)"
                }
                nostrConnectURL = url
                generateQRCode(from: url)

                // Start listening for connection immediately
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
            _ = try await signer.connect()

            // Call addSession FIRST before any UI changes
            let session = try await authManager.addSession(signer)
            let sessionCount = authManager.availableSessions.count

            // Now show success (view might change, but keychain writes are done)
            let debugMsg = "LOGIN COMPLETE!\n\nSession ID: \(session.id.prefix(20))...\nSessions stored: \(sessionCount)\nSignerType: \(session.signerType ?? "nil")"
            await MainActor.run {
                isWaitingForConnection = false
                debugSuccessMessage = debugMsg
                showDebugSuccess = true
            }
        } catch {
            await MainActor.run {
                isWaitingForConnection = false
                errorMessage = "LOGIN FAILED: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func connectWithInput() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        isLoading = true
        defer { isLoading = false }

        do {
            if trimmed.hasPrefix("nsec1") {
                let signer = try NDKPrivateKeySigner(nsec: trimmed)
                _ = try await authManager.addSession(signer)
                dismiss()
            } else if trimmed.hasPrefix("bunker://") || trimmed.hasPrefix("nostrconnect://") {
                let signer = try await NDKBunkerSigner.bunker(ndk: ndk, connectionToken: trimmed)
                _ = try await signer.connect()
                _ = try await authManager.addSession(signer)
                dismiss()
            } else {
                errorMessage = "Invalid input. Enter an nsec or bunker:// URI."
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
