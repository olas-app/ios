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
    @State private var showQRCode = false

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
            ScrollView {
                VStack(spacing: 24) {
                    // Reconnect banner
                    if let session = reconnectSession {
                        reconnectBanner(session: session)
                    }

                    // Header
                    headerSection

                    // Signer hero button (when detected and not reconnecting)
                    if !isReconnecting, let signer = detectedSigner, let url = nostrConnectURL {
                        signerHeroButton(signer: signer, connectURL: url)

                        dividerRow
                    }

                    // Input field
                    inputSection

                    // QR Code toggle
                    qrCodeToggle
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
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

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image("OlasLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(isReconnecting ? "Reconnect Signer" : "Welcome to Olas")
                .font(.title2.weight(.bold))

            Text(isReconnecting ? "Re-authorize your signer to continue" : "Sign in with your Nostr identity")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Reconnect Banner

    private func reconnectBanner(session: NDKSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            Text(formatPubkey(session.pubkey))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(14)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatPubkey(_ pubkey: String) -> String {
        if let npub = try? Bech32.npub(from: pubkey) {
            return "\(npub.prefix(12))...\(npub.suffix(8))"
        }
        return "\(pubkey.prefix(12))...\(pubkey.suffix(8))"
    }

    // MARK: - Signer Hero Button

    private func signerHeroButton(signer: KnownSigner, connectURL: String) -> some View {
        Button {
            openSignerApp(connectURL: connectURL)
        } label: {
            HStack(spacing: 14) {
                if signer == .primal {
                    Image("PrimalLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: signer.icon)
                        .font(.title2)
                }

                Text("Continue with \(signer.name)")
                    .font(.headline)

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(OlasTheme.Colors.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Divider

    private var dividerRow: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)

            Text("or")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
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
                    Group {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Connect")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .background(OlasTheme.Colors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(isLoading)
            }
        }
    }

    // MARK: - QR Code Toggle

    private var qrCodeToggle: some View {
        VStack(spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showQRCode.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.subheadline)
                    Text(showQRCode ? "Hide QR Code" : "Show QR Code")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }

            if showQRCode {
                qrCodeSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - QR Code Section

    private var qrCodeSection: some View {
        VStack(spacing: 16) {
            if let qrCode = qrCodeImage {
                Image(uiImage: qrCode)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: 200)
                    .padding(20)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .onTapGesture {
                        if let urlString = nostrConnectURL, let url = URL(string: urlString) {
                            openURL(url)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 200, height: 200)
                    .overlay { ProgressView() }
            }

            VStack(spacing: 4) {
                Text(isReconnecting ? "Scan to reconnect your signer" : "Scan with your Nostr signer")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
