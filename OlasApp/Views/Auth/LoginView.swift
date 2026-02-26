import CoreImage.CIFilterBuiltins
import NDKSwiftCore
import SwiftUI

public struct LoginView: View {
    var authManager: NDKAuthManager
    var ndk: NDK
    var reconnectSession: NDKSession?
    var onReconnected: (() -> Void)?

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

    private var isReconnecting: Bool { reconnectSession != nil }

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

    public init(authManager: NDKAuthManager, ndk: NDK, reconnectSession: NDKSession? = nil, onReconnected: (() -> Void)? = nil) {
        self.authManager = authManager
        self.ndk = ndk
        self.reconnectSession = reconnectSession
        self.onReconnected = onReconnected
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Reconnect banner
                if let session = reconnectSession {
                    reconnectBanner(session: session)
                }

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
        }
        .task {
            detectSignerApps()
            await generateNostrConnectQR()
        }
    }

    // MARK: - Reconnect Banner

    private func reconnectBanner(session: NDKSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Reconnect Signer")
                    .font(.subheadline.weight(.semibold))

                Text(formatPubkey(session.pubkey))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func formatPubkey(_ pubkey: String) -> String {
        if let npub = try? Bech32.npub(from: pubkey) {
            return "\(npub.prefix(12))...\(npub.suffix(8))"
        }
        return "\(pubkey.prefix(12))...\(pubkey.suffix(8))"
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
                Text(isReconnecting ? "Scan to reconnect your signer" : "Scan with your Nostr signer")
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
        VStack(alignment: .leading, spacing: 8) {
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

#if DEBUG
            if signer == .primal {
                Text("Debug URL: \(buildSignerOpenURLString(connectURL: connectURL))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
#endif
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TextField(isReconnecting ? "bunker://" : "nsec or bunker://", text: $inputText)
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
        let urlToOpen = buildSignerOpenURLString(connectURL: connectURL)
#if DEBUG
        print("[LoginView] Opening signer URL: \(urlToOpen)")
#endif

        if let url = URL(string: urlToOpen) {
            openURL(url)
        }
    }

    private func buildSignerOpenURLString(connectURL: String) -> String {
        // Add callback for return-to-app flow when opening via detected signer.
        var urlWithCallback = connectURL
        let callback = "olas://nip46"
        if let encodedCallback = callback.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            urlWithCallback += "&callback=\(encodedCallback)"
        }
        return urlWithCallback
    }

    private func generateNostrConnectQR() async {
        do {
            let relays = ["wss://relay.primal.net"]
            let localSigner = try NDKPrivateKeySigner.generate()

            let options = NDKBunkerSigner.NostrConnectOptions(
                name: "Olas",
                url: "https://olas.app",
                image: "https://olas.app/icon.png",
                perms: "sign_event:1,sign_event:7,sign_event:20,sign_event:22,sign_event:1111,sign_event:24242,nip04_encrypt,nip04_decrypt,nip44_encrypt,nip44_decrypt"
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

            if let url = url {
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
            let connectedPubkey = try await signer.connect()

            if let session = reconnectSession {
                // Reconnect mode: validate pubkey matches
                guard connectedPubkey == session.pubkey else {
                    await MainActor.run {
                        isWaitingForConnection = false
                        errorMessage = "The signer returned a different account. Please use the correct signer for this account."
                        showError = true
                    }
                    return
                }

                try await authManager.updateSessionSigner(session, signer: signer)
                await MainActor.run {
                    isWaitingForConnection = false
                    onReconnected?()
                    dismiss()
                }
            } else {
                // Login mode: add new session
                _ = try await authManager.addSession(signer)
                await MainActor.run {
                    isWaitingForConnection = false
                    dismiss()
                }
            }
        } catch {
            await MainActor.run {
                isWaitingForConnection = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func connectWithInput() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        isLoading = true
        defer { isLoading = false }

        do {
            if let session = reconnectSession {
                // Reconnect mode: only bunker:// allowed
                if trimmed.hasPrefix("nsec1") {
                    errorMessage = "Private key login cannot be used for reconnection. Use a bunker:// URI from your signer app."
                    showError = true
                    return
                }

                guard trimmed.hasPrefix("bunker://") || trimmed.hasPrefix("nostrconnect://") else {
                    errorMessage = "Enter a bunker:// URI from your signer app."
                    showError = true
                    return
                }

                let signer = try await NDKBunkerSigner.bunker(ndk: ndk, connectionToken: trimmed)
                let connectedPubkey = try await signer.connect()

                guard connectedPubkey == session.pubkey else {
                    errorMessage = "The signer returned a different account. Please use the correct signer for this account."
                    showError = true
                    return
                }

                try await authManager.updateSessionSigner(session, signer: signer)
                onReconnected?()
                dismiss()
            } else {
                // Login mode: unchanged behavior
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
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
