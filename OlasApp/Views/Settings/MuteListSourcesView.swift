// MuteListSourcesView.swift
import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

/// Settings view for managing mute list sources.
/// Users can add sources via NIP-05 or npub, and see profile info for each source.
struct MuteListSourcesView: View {
    let ndk: NDK

    @Environment(SettingsManager.self) private var settings
    @EnvironmentObject private var muteListManager: MuteListManager

    @State private var showAddSheet = false
    @State private var sourceToDelete: String?

    var body: some View {
        List {
            Section {
                ForEach(settings.muteListSources, id: \.self) { pubkey in
                    MuteSourceRow(ndk: ndk, pubkey: pubkey)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                removeSource(pubkey)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Source", systemImage: "plus.circle.fill")
                        .foregroundStyle(OlasTheme.Colors.accent)
                }
            } header: {
                Text("Mute List Sources")
            } footer: {
                Text("Events from authors muted by any of these accounts will be hidden from your feed.")
            }

            if settings.muteListSources != OlasConstants.defaultMuteListSources {
                Section {
                    Button {
                        resetToDefaults()
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Mute Sources")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            AddMuteSourceSheet(ndk: ndk) { pubkey in
                addSource(pubkey)
            }
        }
    }

    private func addSource(_ pubkey: String) {
        settings.addMuteListSource(pubkey)
        muteListManager.updateMuteListSources(settings.muteListSources)
    }

    private func removeSource(_ pubkey: String) {
        settings.removeMuteListSource(pubkey)
        muteListManager.updateMuteListSources(settings.muteListSources)
    }

    private func resetToDefaults() {
        settings.resetMuteListSourcesToDefaults()
        muteListManager.updateMuteListSources(settings.muteListSources)
    }
}

// MARK: - Mute Source Row

/// Displays a single mute source with profile picture and name
private struct MuteSourceRow: View {
    let ndk: NDK
    let pubkey: String

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
        }
        .padding(.vertical, 4)
    }

    private var formattedPubkey: String {
        if let npub = try? Bech32.npub(pubkey) {
            return String(npub.prefix(16)) + "..." + String(npub.suffix(8))
        }
        return String(pubkey.prefix(12)) + "..."
    }
}

// MARK: - Add Mute Source Sheet

/// Sheet for adding a new mute source via NIP-05 or npub
private struct AddMuteSourceSheet: View {
    let ndk: NDK
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var isResolving = false
    @State private var resolvedPubkey: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Input field
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
                }
                .padding(.horizontal)

                // Resolved preview
                if isResolving {
                    ProgressView("Resolving...")
                        .padding()
                } else if let pubkey = resolvedPubkey {
                    ResolvedUserPreview(ndk: ndk, pubkey: pubkey)
                        .padding(.horizontal)
                } else if let error = errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding()
                }

                Spacer()

                // Add button
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
                        .background(resolvedPubkey != nil ? OlasTheme.Colors.accent : Color.gray)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(resolvedPubkey == nil)
                .padding(.horizontal)
                .padding(.bottom)
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
                // Clear previous resolution when input changes
                resolvedPubkey = nil
                errorMessage = nil
            }
            .onSubmit {
                resolveInput()
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
                await MainActor.run {
                    resolvedPubkey = pubkey
                    isResolving = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isResolving = false
                }
            }
        }
    }

    private func resolveToPublicKey(_ input: String) async throws -> String {
        // Check if it's an npub
        if input.hasPrefix("npub1") {
            if let user = try? NDKUser(npub: input, ndk: ndk) {
                return user.pubkey
            }
            throw ResolutionError.invalidNpub
        }

        // Check if it's a hex pubkey
        if input.count == 64, input.allSatisfy({ $0.isHexDigit }) {
            return input
        }

        // Try NIP-05 resolution
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

    var body: some View {
        HStack(spacing: 12) {
            NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 56)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                    .font(.headline)

                if let npub = try? Bech32.npub(pubkey) {
                    Text(String(npub.prefix(20)) + "...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
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
