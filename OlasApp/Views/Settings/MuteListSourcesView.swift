// MuteListSourcesView.swift
import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

/// Settings view for managing mute list sources.
/// Users can add sources via NIP-05 or npub, and see profile info for each source.
struct MuteListSourcesView: View {
    let ndk: NDK

    @Environment(SettingsManager.self) private var settings
    @Environment(MuteListManager.self) private var muteListManager

    @State private var showAddSheet = false

    var body: some View {
        List {
            Section {
                ForEach(settings.muteListSources, id: \.self) { pubkey in
                    MuteSourceRow(ndk: ndk, pubkey: pubkey, mutedCount: muteListManager.mutedCount(bySource: pubkey))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                settings.removeMuteListSource(pubkey)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Swipe left to remove this mute source")
                }

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Source", systemImage: "plus.circle.fill")
                        .foregroundStyle(OlasTheme.Colors.accent)
                }
                .accessibilityHint("Add a new account whose mute list will filter your feed")
            } header: {
                Text("Mute List Sources")
            } footer: {
                Text("Events from authors muted by any of these accounts will be hidden from your feed.")
            }

            if settings.muteListSources != OlasConstants.defaultMuteListSources {
                Section {
                    Button {
                        settings.resetMuteListSourcesToDefaults()
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHint("Restore the default mute list sources")
                }
            }
        }
        .navigationTitle("Mute Sources")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            AddMuteSourceSheet(ndk: ndk, existingSources: settings.muteListSources) { pubkey in
                settings.addMuteListSource(pubkey)
            }
        }
    }
}

// MARK: - Mute Source Row

/// Displays a single mute source with profile picture and name
private struct MuteSourceRow: View {
    let ndk: NDK
    let pubkey: String
    let mutedCount: Int

    var body: some View {
        HStack(spacing: 12) {
            NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 44)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                    .font(.subheadline.weight(.semibold))

                Text(formattedPubkey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if mutedCount > 0 {
                Text("\(mutedCount)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                    .accessibilityLabel("\(mutedCount) muted accounts")
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedPubkey: String {
        if let npub = try? Bech32.npub(from: pubkey) {
            return String(npub.prefix(16)) + "..." + String(npub.suffix(8))
        }
        return String(pubkey.prefix(12)) + "..."
    }
}

// MARK: - Add Mute Source Sheet

/// Sheet for adding a new mute source via NIP-05 or npub
private struct AddMuteSourceSheet: View {
    let ndk: NDK
    let existingSources: [String]
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var isResolving = false
    @State private var resolvedPubkey: String?
    @State private var errorMessage: String?

    private var isDuplicate: Bool {
        guard let pubkey = resolvedPubkey else { return false }
        return existingSources.contains(pubkey)
    }

    private var canAdd: Bool {
        resolvedPubkey != nil && !isDuplicate
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter NIP-05 or npub")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("user@example.com or npub1...", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            resolveInput()
                        }
                        .accessibilityLabel("NIP-05 address or npub")
                        .accessibilityHint("Enter the NIP-05 address like user@domain.com or an npub")
                }
                .padding(.horizontal)

                if isResolving {
                    ProgressView("Resolving...")
                        .padding()
                } else if let pubkey = resolvedPubkey {
                    VStack(spacing: 8) {
                        ResolvedUserPreview(ndk: ndk, pubkey: pubkey, isDuplicate: isDuplicate)
                            .padding(.horizontal)

                        if isDuplicate {
                            Text("This source is already in your list")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                } else if let error = errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding()
                        .accessibilityLabel("Error: \(error)")
                }

                Spacer()

                Button {
                    if let pubkey = resolvedPubkey {
                        onAdd(pubkey)
                        dismiss()
                    }
                } label: {
                    Text("Add Source")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OlasTheme.Colors.accent)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(!canAdd)
                .opacity(canAdd ? 1.0 : 0.5)
                .padding(.horizontal)
                .padding(.bottom)
                .accessibilityHint(isDuplicate ? "Cannot add: this source already exists" : "Add this account as a mute source")
            }
            .navigationTitle("Add Mute Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: inputText) { _, _ in
                resolvedPubkey = nil
                errorMessage = nil
            }
        }
    }

    private func resolveInput() {
        let input = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        isResolving = true
        errorMessage = nil
        resolvedPubkey = nil

        Task {
            do {
                let pubkey = try await resolveToPublicKey(input)
                resolvedPubkey = pubkey
                isResolving = false
            } catch {
                errorMessage = error.localizedDescription
                isResolving = false
            }
        }
    }

    private func resolveToPublicKey(_ input: String) async throws -> String {
        if input.hasPrefix("npub1") {
            if let user = try? NDKUser(npub: input, ndk: ndk) {
                return user.pubkey
            }
            throw ResolutionError.invalidNpub
        }

        if input.count == 64, input.allSatisfy({ $0.isHexDigit }) {
            return input
        }

        let nip05 = input.contains("@") ? input : "_@\(input)"
        if let user = try? await NDKUser.fromNip05(nip05, ndk: ndk) {
            return user.pubkey
        }

        throw ResolutionError.nip05NotFound
    }
}

// MARK: - Resolved User Preview

/// Shows a preview of the resolved user before adding
private struct ResolvedUserPreview: View {
    let ndk: NDK
    let pubkey: String
    let isDuplicate: Bool

    var body: some View {
        HStack(spacing: 12) {
            NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 56)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                    .font(.headline)

                if let npub = try? Bech32.npub(from: pubkey) {
                    Text(String(npub.prefix(20)) + "...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: isDuplicate ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(isDuplicate ? .orange : .green)
                .accessibilityLabel(isDuplicate ? "Already added" : "Ready to add")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Resolution Error

private enum ResolutionError: LocalizedError {
    case invalidNpub
    case nip05NotFound

    var errorDescription: String? {
        switch self {
        case .invalidNpub:
            return "Invalid npub format"
        case .nip05NotFound:
            return "Could not find user with that NIP-05 address"
        }
    }
}
