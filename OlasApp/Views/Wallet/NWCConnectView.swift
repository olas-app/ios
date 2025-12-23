// NWCConnectView.swift

import SwiftUI

public struct NWCConnectView: View {
    @Environment(\.dismiss) private var dismiss
    var walletManager: NWCWalletManager

    @State private var connectionState: ConnectionState = .idle
    @State private var installedWallets: [NWCWallet] = []
    @State private var awaitingCallback = false
    @State private var showManualEntry = false
    @State private var connectionURI = ""
    @State private var errorMessage: String?
    @State private var showDebugAlert = false
    @State private var debugURLString = ""
    @State private var pendingWalletName = ""

    enum ConnectionState: Equatable {
        case idle
        case detectingWallets
        case waitingForCallback(walletName: String)
        case connecting
        case connected
        case error(String)
    }

    public init(walletManager: NWCWalletManager) {
        self.walletManager = walletManager
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // Subtle gradient background
                LinearGradient(
                    colors: [Color(.systemBackground), OlasTheme.Colors.accent.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        headerSection

                        if !installedWallets.isEmpty {
                            walletSelectionSection
                        }

                        manualEntryButton
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Connect Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showManualEntry) {
                ManualEntrySheet(
                    connectionURI: $connectionURI,
                    errorMessage: $errorMessage,
                    isConnecting: connectionState == .connecting,
                    onConnect: {
                        showManualEntry = false
                        await connectWithURI()
                    },
                    onDismiss: {
                        showManualEntry = false
                    }
                )
            }
            .task {
                await detectWallets()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if awaitingCallback {
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        if awaitingCallback {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                connectionState = .idle
                                awaitingCallback = false
                            }
                        }
                    }
                }
            }
            .alert("NWC Deep Link URL", isPresented: $showDebugAlert) {
                Button("Copy") {
                    UIPasteboard.general.string = debugURLString
                }
                Button("Open", role: .cancel) {
                    if let url = URL(string: debugURLString) {
                        Task {
                            await openDeepLink(url)
                        }
                    }
                }
            } message: {
                Text(debugURLString)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(OlasTheme.Colors.accent.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: stateIcon)
                    .font(.system(size: 44))
                    .foregroundStyle(stateIconColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: isWaitingForCallback)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: connectionState)

            Text(stateTitle)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.2), value: connectionState)

            Text(stateSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.2), value: connectionState)
        }
    }

    private var stateIcon: String {
        switch connectionState {
        case .idle, .detectingWallets:
            return "link.circle.fill"
        case .waitingForCallback:
            return "arrow.triangle.2.circlepath"
        case .connecting:
            return "wifi"
        case .connected:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var stateIconColor: Color {
        switch connectionState {
        case .idle, .detectingWallets, .waitingForCallback, .connecting:
            return OlasTheme.Colors.accent
        case .connected:
            return .green
        case .error:
            return .red
        }
    }

    private var stateTitle: String {
        switch connectionState {
        case .idle:
            return "Connect Your Wallet"
        case .detectingWallets:
            return "Detecting Wallets..."
        case let .waitingForCallback(walletName):
            return "Waiting for \(walletName)"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected!"
        case let .error(message):
            return message
        }
    }

    private var stateSubtitle: String {
        switch connectionState {
        case .idle:
            return "Link your Lightning wallet to send and receive payments"
        case .detectingWallets:
            return "Looking for compatible wallet apps"
        case .waitingForCallback:
            return "Approve the connection in your wallet app"
        case .connecting:
            return "Establishing secure connection"
        case .connected:
            return "Your wallet is ready to use"
        case .error:
            return "Please try again"
        }
    }

    private var isWaitingForCallback: Bool {
        if case .waitingForCallback = connectionState {
            return true
        }
        return false
    }

    // MARK: - Wallet Selection Section

    private var walletSelectionSection: some View {
        VStack(spacing: 20) {
            HStack(spacing: 24) {
                ForEach(installedWallets) { wallet in
                    WalletIconButton(
                        wallet: wallet,
                        isConnecting: connectionState == .waitingForCallback(walletName: wallet.name)
                    ) {
                        await connectViaDeepLink(wallet)
                    }
                }
            }
        }
    }

    // MARK: - Manual Entry Button

    private var manualEntryButton: some View {
        VStack(spacing: 16) {
            if !installedWallets.isEmpty {
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)

                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                }
            }

            Button {
                showManualEntry = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.title3)
                    Text("Enter manually")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(.systemGray6))
                .foregroundStyle(.primary)
                .cornerRadius(14)
            }
        }
    }

    // MARK: - Actions

    private func detectWallets() async {
        connectionState = .detectingWallets
        installedWallets = await walletManager.detectInstalledWallets()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            connectionState = .idle
        }
    }

    private func connectViaDeepLink(_ wallet: NWCWallet) async {
        guard let url = walletManager.buildDeepLinkURL(wallet: wallet) else {
            withAnimation {
                connectionState = .error("Failed to build connection URL")
            }
            return
        }

        // Show debug alert with the URL
        debugURLString = url.absoluteString
        pendingWalletName = wallet.name
        showDebugAlert = true
    }

    private func openDeepLink(_ url: URL) async {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            connectionState = .waitingForCallback(walletName: pendingWalletName)
            awaitingCallback = true
        }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        await UIApplication.shared.open(url)
    }

    private func connectWithURI() async {
        guard !connectionURI.isEmpty else { return }

        errorMessage = nil
        connectionState = .connecting

        do {
            try await walletManager.connect(walletConnectURI: connectionURI)

            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                connectionState = .connected
            }

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            try? await Task.sleep(for: .milliseconds(800))
            dismiss()
        } catch {
            withAnimation {
                connectionState = .error("Connection failed")
                errorMessage = error.localizedDescription
            }

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
}

// MARK: - Wallet Icon Button

private struct WalletIconButton: View {
    let wallet: NWCWallet
    let isConnecting: Bool
    let onTap: () async -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            Task {
                await onTap()
            }
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    if wallet.iconIsAsset {
                        Image(wallet.iconName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(OlasTheme.Colors.accent.opacity(0.1))
                            .frame(width: 64, height: 64)
                            .overlay {
                                Image(systemName: wallet.iconName)
                                    .font(.system(size: 28))
                                    .foregroundStyle(OlasTheme.Colors.accent)
                            }
                    }

                    if isConnecting {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .frame(width: 64, height: 64)
                            .overlay {
                                ProgressView()
                            }
                    }
                }

                Text(wallet.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isConnecting)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Manual Entry Sheet

private struct ManualEntrySheet: View {
    @Binding var connectionURI: String
    @Binding var errorMessage: String?
    let isConnecting: Bool
    let onConnect: () async -> Void
    let onDismiss: () -> Void

    @State private var showScanner = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showScanner {
                    QRScannerView { scannedCode in
                        connectionURI = scannedCode
                        Task {
                            await onConnect()
                        }
                    }
                    .frame(maxHeight: .infinity)
                }

                VStack(spacing: 16) {
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }

                    Button {
                        pasteFromClipboard()
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                            Text("Paste")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OlasTheme.Colors.accent)
                        .cornerRadius(14)
                    }
                }
                .padding(24)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Scan or Paste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
        }
    }

    private func pasteFromClipboard() {
        if let pastedString = UIPasteboard.general.string {
            connectionURI = pastedString
            Task {
                await onConnect()
            }
        }
    }
}
