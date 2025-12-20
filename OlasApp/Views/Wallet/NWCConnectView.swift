// NWCConnectView.swift

import SwiftUI

public struct NWCConnectView: View {
    @Environment(\.dismiss) private var dismiss
    var walletManager: NWCWalletManager

    @State private var connectionURI: String = ""
    @State private var showScanner = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    public init(walletManager: NWCWalletManager) {
        self.walletManager = walletManager
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(OlasTheme.Colors.accent)

                        Text("Connect to NWC Wallet")
                            .font(.title2.bold())

                        Text("Enter your Nostr Wallet Connect URI to connect your Lightning wallet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 32)

                    // URI Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wallet Connect URI")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        TextField("nostr+walletconnect://...", text: $connectionURI, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.caption.monospaced())
                    }
                    .padding(.horizontal)

                    // QR Code Scanner Button
                    Button {
                        showScanner = true
                    } label: {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                            Text("Scan QR Code")
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Error Message
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }

                    // Connect Button
                    Button {
                        Task {
                            await connectWallet()
                        }
                    } label: {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isConnecting ? "Connecting..." : "Connect")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(connectionURI.isEmpty || isConnecting ? Color(.systemGray4) : OlasTheme.Colors.accent)
                        .cornerRadius(12)
                    }
                    .disabled(connectionURI.isEmpty || isConnecting)
                    .padding(.horizontal)

                    // Info Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to get your connection URI:")
                            .font(.subheadline.weight(.semibold))

                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(icon: "1.circle.fill", text: "Open your NWC-compatible wallet (Alby, Mutiny, Zeus, etc.)")
                            InfoRow(icon: "2.circle.fill", text: "Find the \"Nostr Wallet Connect\" or \"NWC\" settings")
                            InfoRow(icon: "3.circle.fill", text: "Generate or copy your connection string")
                            InfoRow(icon: "4.circle.fill", text: "Paste it here or scan the QR code")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    Spacer()
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
            .sheet(isPresented: $showScanner) {
                QRScannerView { scannedCode in
                    connectionURI = scannedCode
                    showScanner = false
                }
            }
        }
    }

    private func connectWallet() async {
        guard !connectionURI.isEmpty else { return }

        isConnecting = true
        errorMessage = nil

        do {
            try await walletManager.connect(walletConnectURI: connectionURI)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isConnecting = false
    }

}

private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(OlasTheme.Colors.accent)
                .frame(width: 24)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
