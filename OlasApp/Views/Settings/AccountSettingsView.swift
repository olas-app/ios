import NDKSwiftCore
import Security
import SwiftUI

struct AccountSettingsView: View {
    @Environment(NDKAuthManager.self) private var authManager
    @State private var showNsec = false
    @State private var nsec: String?
    @State private var npub: String?
    @State private var bunkerUri: String?
    @State private var copiedMessage: String?
    @State private var isRemoteSigner = false

    var body: some View {
        List {
            Section("Public Key") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your npub (shareable)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(npub ?? "Loading...")
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button {
                            if let npub { copyToClipboard(npub, label: "npub") }
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
            }

            // Only show private key backup section for local signers
            if !isRemoteSigner {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Back up your private key", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)

                        Text("Your private key (nsec) is the only way to recover your account. Store it securely and never share it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if showNsec, let nsec {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(nsec)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding()
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)

                                Button {
                                    copyToClipboard(nsec, label: "nsec")
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.on.doc")
                                        Text("Copy Private Key")
                                    }
                                }
                                .buttonStyle(.glass)
                            }
                        } else {
                            Button {
                                showNsec = true
                            } label: {
                                HStack {
                                    Image(systemName: "eye")
                                    Text("Reveal Private Key")
                                }
                            }
                            .buttonStyle(.glass)
                        }
                    }
                } header: {
                    Text("Private Key Backup")
                } footer: {
                    Text("Keep your private key safe. Anyone with access to it controls your account.")
                }
            }

            // Show remote signer info if using NIP-46
            if isRemoteSigner {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Remote Signer", systemImage: "network")
                            .foregroundStyle(.blue)

                        Text("You're using a remote signer via NIP-46. Your keys are managed by your remote signing app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let bunkerUri {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Bunker URI")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(bunkerUri)
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .padding()
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)

                                Button {
                                    copyToClipboard(bunkerUri, label: "Bunker URI")
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.on.doc")
                                        Text("Copy Bunker URI")
                                    }
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }
                } header: {
                    Text("Signer Information")
                } footer: {
                    Text("Events are signed remotely. Manage your keys in your remote signing app.")
                }
            }

            if let message = copiedMessage {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(message)
                    }
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadKeys()
        }
    }

    private func loadKeys() {
        // Get npub from activePubkey
        if let pubkey = authManager.activePubkey {
            npub = try? Bech32.npub(from: pubkey)
        }

        // Check if using a private key signer or remote signer
        if let privateKeySigner = authManager.activeSigner as? NDKPrivateKeySigner {
            // Local signer - show private key
            isRemoteSigner = false
            nsec = try? privateKeySigner.nsec
        } else if authManager.activeSigner is NDKBunkerSigner {
            // Remote signer
            isRemoteSigner = true
            // Note: bunker URI is managed by NDKAuthManager now, not stored separately
            bunkerUri = nil
        }
    }

    private func copyToClipboard(_ value: String, label: String) {
        UIPasteboard.general.string = value
        copiedMessage = "\(label) copied to clipboard"
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedMessage = nil
        }
    }
}
