import NDKSwiftCore
import SwiftUI

struct OutboxInspectorView: View {
    let ndk: NDK

    @State private var trackedItems: [NDKOutboxItem] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading outbox data...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Summary Section
                Section("Overview") {
                    QuickStatRow(label: "Tracked Users", value: "\(trackedItems.count)")
                    QuickStatRow(label: "Unique Relays", value: "\(uniqueRelayCount)")
                    QuickStatRow(label: "Avg Read Relays", value: String(format: "%.1f", averageReadRelays))
                    QuickStatRow(label: "Avg Write Relays", value: String(format: "%.1f", averageWriteRelays))
                }

                // Navigation Section
                Section("Inspection Tools") {
                    NavigationLink(destination: OutboxTrackedUsersView(ndk: ndk, trackedItems: trackedItems)) {
                        ToolRow(
                            icon: "person.2",
                            title: "Tracked Users",
                            subtitle: "\(trackedItems.count) users with relay preferences",
                            color: .blue
                        )
                    }

                    NavigationLink(destination: OutboxRelayMappingView(ndk: ndk, trackedItems: trackedItems)) {
                        ToolRow(
                            icon: "point.3.connected.trianglepath.dotted",
                            title: "Relay Mapping",
                            subtitle: "Which users use which relays",
                            color: .green
                        )
                    }

                    NavigationLink(destination: OutboxLiveStatsView(ndk: ndk)) {
                        ToolRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Live Stats",
                            subtitle: "Real-time discovery and updates",
                            color: .orange
                        )
                    }
                }
            }
        }
        .navigationTitle("Outbox Inspector")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
    }

    private var uniqueRelayCount: Int {
        var allRelays = Set<String>()
        for item in trackedItems {
            allRelays.formUnion(item.allRelayURLs)
        }
        return allRelays.count
    }

    private var averageReadRelays: Double {
        guard !trackedItems.isEmpty else { return 0 }
        let total = trackedItems.reduce(0) { $0 + $1.readRelays.count }
        return Double(total) / Double(trackedItems.count)
    }

    private var averageWriteRelays: Double {
        guard !trackedItems.isEmpty else { return 0 }
        let total = trackedItems.reduce(0) { $0 + $1.writeRelays.count }
        return Double(total) / Double(trackedItems.count)
    }

    private func loadData() async {
        isLoading = true

        trackedItems = await ndk.outbox.getAllCachedItems()

        isLoading = false
    }
}

// MARK: - Supporting Views

private struct QuickStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ToolRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
