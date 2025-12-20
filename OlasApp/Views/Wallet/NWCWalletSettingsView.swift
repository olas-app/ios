// NWCWalletSettingsView.swift
import SwiftUI

public struct NWCWalletSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var walletManager: NWCWalletManager

    @State private var showDisconnectAlert = false
    @State private var showConnectionURI = false

    public init(walletManager: NWCWalletManager) {
        self.walletManager = walletManager
    }

    public var body: some View {
        List {
            // Wallet Info Section
            Section("Wallet Information") {
                if let info = walletManager.walletInfo {
                    if let alias = info.alias {
                        LabeledContent("Alias", value: alias)
                    }

                    if let pubkey = info.pubkey {
                        LabeledContent("Public Key") {
                            Text(pubkey.prefix(16) + "...")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let network = info.network {
                        LabeledContent("Network", value: network)
                    }

                    LabeledContent("Supported Methods") {
                        Text("\(info.methods.count) methods")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Status") {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Connection Section
            Section("Connection") {
                Button {
                    showConnectionURI = true
                } label: {
                    HStack {
                        Text("View Connection URI")
                        Spacer()
                        Image(systemName: "eye")
                            .foregroundStyle(.secondary)
                    }
                }

                Button(role: .destructive) {
                    showDisconnectAlert = true
                } label: {
                    Text("Disconnect Wallet")
                }
            }

            // About Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About NWC")
                        .font(.subheadline.weight(.semibold))

                    Text("Nostr Wallet Connect (NWC) allows you to connect a remote Lightning wallet to this app. Your wallet keys remain on the remote wallet service, and payments are authorized through encrypted Nostr messages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("NWC Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert("Disconnect Wallet?", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task {
                    await walletManager.disconnect(clearURI: true)
                    dismiss()
                }
            }
        } message: {
            Text("This will disconnect your wallet and remove the stored connection. You'll need to reconnect with your wallet URI to use it again.")
        }
        .sheet(isPresented: $showConnectionURI) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Connection URI")
                            .font(.headline)

                        if let uri = walletManager.retrieveConnectionURI() {
                            Text(uri)
                                .font(.caption.monospaced())
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .textSelection(.enabled)

                            Button {
                                UIPasteboard.general.string = uri
                            } label: {
                                HStack {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copy to Clipboard")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(OlasTheme.Colors.accent)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                            }
                        } else {
                            Text("No connection URI found")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                .navigationTitle("Connection URI")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showConnectionURI = false
                        }
                    }
                }
            }
        }
    }

    private var statusText: String {
        switch walletManager.connectionStatus {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case let .error(msg): return "Error: \(msg)"
        }
    }

    private var statusColor: Color {
        switch walletManager.connectionStatus {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
}
