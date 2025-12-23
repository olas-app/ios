import NDKSwiftCore
import SwiftUI

struct OutboxTrackedUsersView: View {
    let ndk: NDK
    let trackedItems: [NDKOutboxItem]

    @State private var selectedItem: NDKOutboxItem?
    @State private var showingDetail = false

    var body: some View {
        List {
            if trackedItems.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No tracked users")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                Section("Tracked Users (\(trackedItems.count))") {
                    ForEach(sortedItems, id: \.pubkey) { item in
                        TrackedUserRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItem = item
                                showingDetail = true
                            }
                    }
                }
            }
        }
        .navigationTitle("Tracked Users")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .sheet(isPresented: $showingDetail) {
                if let item = selectedItem {
                    NavigationStack {
                        TrackedUserDetailView(ndk: ndk, item: item)
                    }
                }
            }
    }

    private var sortedItems: [NDKOutboxItem] {
        trackedItems.sorted { item1, item2 in
            let totalRelays1 = item1.readRelays.count + item1.writeRelays.count
            let totalRelays2 = item2.readRelays.count + item2.writeRelays.count
            return totalRelays1 > totalRelays2
        }
    }
}

// MARK: - Tracked User Row

private struct TrackedUserRow: View {
    let item: NDKOutboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Pubkey
            HStack {
                Text(formatPubkey(item.pubkey))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                Spacer()

                // Source badge
                Text(item.source.rawValue.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(sourceBadgeColor)
                    .foregroundStyle(.white)
                    .cornerRadius(4)
            }

            // Relay counts
            HStack(spacing: 16) {
                Label("\(item.readRelays.count) read", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(item.writeRelays.count) write", systemImage: "arrow.up.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formatRelativeDate(item.fetchedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceBadgeColor: Color {
        switch item.source {
        case .nip65:
            return .blue
        case .contactList:
            return .green
        case .manual:
            return .orange
        case .unknown:
            return .gray
        }
    }

    private func formatPubkey(_ key: String) -> String {
        String(key.prefix(8)) + "..."
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Tracked User Detail View

private struct TrackedUserDetailView: View {
    let ndk: NDK
    let item: NDKOutboxItem

    @Environment(\.dismiss) private var dismiss
    @State private var relayScores: [String: Double] = [:]
    @State private var isLoadingScores = true

    var body: some View {
        List {
            // Pubkey Section
            Section("User") {
                HStack {
                    Text(item.pubkey)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = item.pubkey
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }

            // Read Relays Section
            if !item.readRelays.isEmpty {
                Section("Read Relays (\(item.readRelays.count))") {
                    ForEach(Array(item.readRelays.sorted(by: { $0.url < $1.url })), id: \.url) { ndkRelayInfo in
                        NDKRelayInfoRow(
                            relayInfo: ndkRelayInfo,
                            pubkey: item.pubkey,
                            score: relayScores[ndkRelayInfo.url],
                            isLoadingScores: isLoadingScores
                        )
                    }
                }
            }

            // Write Relays Section
            if !item.writeRelays.isEmpty {
                Section("Write Relays (\(item.writeRelays.count))") {
                    ForEach(Array(item.writeRelays.sorted(by: { $0.url < $1.url })), id: \.url) { ndkRelayInfo in
                        NDKRelayInfoRow(
                            relayInfo: ndkRelayInfo,
                            pubkey: item.pubkey,
                            score: relayScores[ndkRelayInfo.url],
                            isLoadingScores: isLoadingScores
                        )
                    }
                }
            }

            // Metadata Section
            Section("Metadata") {
                LabeledContent("Source") {
                    Text(item.source.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Fetched At") {
                    Text(formatDate(item.fetchedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Age") {
                    Text(formatRelativeDate(item.fetchedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("User Details")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadRelayScores()
            }
    }

    private func loadRelayScores() async {
        isLoadingScores = true

        var scores: [String: Double] = [:]

        for relayInfo in item.readRelays.union(item.writeRelays) {
            let score = await ndk.outbox.getRelayScore(relay: relayInfo.url, for: item.pubkey)
            scores[relayInfo.url] = score
        }

        relayScores = scores
        isLoadingScores = false
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - NDK Relay Info Row

private struct NDKRelayInfoRow: View {
    let relayInfo: NDKSwiftCore.RelayInfo
    let pubkey: String
    let score: Double?
    let isLoadingScores: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Relay URL
            Text(formatRelayURL(relayInfo.url))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)

            // Metadata row
            HStack(spacing: 12) {
                // Score
                if isLoadingScores {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading...")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else if let score = score {
                    Label(formatScore(score), systemImage: "chart.bar")
                        .font(.caption2)
                        .foregroundStyle(scoreColor(score))
                }

                if let metadata = relayInfo.metadata {
                    // Response time
                    if let avgResponseTime = metadata.avgResponseTime {
                        Label(formatResponseTime(avgResponseTime), systemImage: "timer")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Failure count
                    if metadata.failureCount > 0 {
                        Label("\(metadata.failureCount) fails", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    // Auth/payment badges
                    if metadata.authRequired {
                        Text("AUTH")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .cornerRadius(3)
                    }

                    if metadata.paymentRequired {
                        Text("PAID")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple)
                            .foregroundStyle(.white)
                            .cornerRadius(3)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func formatRelayURL(_ url: String) -> String {
        url.replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
    }

    private func formatScore(_ score: Double) -> String {
        String(format: "%.2f", score)
    }

    private func formatResponseTime(_ ms: Double) -> String {
        String(format: "%.0fms", ms)
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.8 {
            return .green
        } else if score >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
}
