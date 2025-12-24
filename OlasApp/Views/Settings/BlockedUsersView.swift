// BlockedUsersView.swift
import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

/// Displays all blocked/muted users from personal mute list and centralized sources
struct BlockedUsersView: View {
    let ndk: NDK

    @Environment(MuteListManager.self) private var muteListManager
    @Environment(SettingsManager.self) private var settings

    @State private var selectedSegment = 0

    private var userMutedList: [String] {
        Array(muteListManager.userMutedPubkeys).sorted()
    }

    private var sourceMutedList: [String] {
        Array(muteListManager.centralizedMutedPubkeys).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $selectedSegment) {
                Text("Your Mutes (\(userMutedList.count))").tag(0)
                Text("From Sources (\(sourceMutedList.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if selectedSegment == 0 {
                userMutesSection
            } else {
                sourceMutesSection
            }
        }
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var userMutesSection: some View {
        if userMutedList.isEmpty {
            emptyState(
                icon: "person.crop.circle.badge.checkmark",
                title: "No Muted Users",
                message: "Users you mute will appear here"
            )
        } else {
            List {
                ForEach(userMutedList, id: \.self) { pubkey in
                    BlockedUserRow(ndk: ndk, pubkey: pubkey, source: nil)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Task {
                                    try? await muteListManager.unmute(pubkey)
                                }
                            } label: {
                                Label("Unmute", systemImage: "speaker.wave.2")
                            }
                            .tint(.green)
                        }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var sourceMutesSection: some View {
        if sourceMutedList.isEmpty {
            emptyState(
                icon: "eye.slash.circle",
                title: "No Source Mutes",
                message: "Users muted by your configured sources will appear here"
            )
        } else {
            List {
                ForEach(sourceMutedList, id: \.self) { pubkey in
                    BlockedUserRow(ndk: ndk, pubkey: pubkey, source: sourceForPubkey(pubkey))
                }
            }
            .listStyle(.plain)
        }
    }

    private func sourceForPubkey(_ pubkey: String) -> String? {
        for source in settings.muteListSources {
            if muteListManager.mutedPubkeys(bySource: source).contains(pubkey) {
                return source
            }
        }
        return nil
    }

    @ViewBuilder
    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Blocked User Row

private struct BlockedUserRow: View {
    let ndk: NDK
    let pubkey: String
    let source: String?

    var body: some View {
        HStack(spacing: 12) {
            NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 44)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                    .font(.subheadline.weight(.semibold))

                if let source = source {
                    SourceLabel(ndk: ndk, sourcePubkey: source)
                } else {
                    Text(formattedPubkey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var formattedPubkey: String {
        if let npub = try? Bech32.npub(from: pubkey) {
            return String(npub.prefix(16)) + "..." + String(npub.suffix(8))
        }
        return String(pubkey.prefix(12)) + "..."
    }
}

// MARK: - Source Label

private struct SourceLabel: View {
    let ndk: NDK
    let sourcePubkey: String

    var body: some View {
        HStack(spacing: 4) {
            Text("via")
                .foregroundStyle(.secondary)
            NDKUIDisplayName(ndk: ndk, pubkey: sourcePubkey)
                .foregroundStyle(OlasTheme.Colors.accent)
        }
        .font(.caption)
        .lineLimit(1)
    }
}
