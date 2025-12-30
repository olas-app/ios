import NDKSwiftCore
import NDKSwiftNostrDB
import SwiftUI

struct DeveloperToolsView: View {
    let ndk: NDK

    @State private var stats: NdbStat?
    @State private var databaseSize: Int64 = 0
    @State private var relayCount: Int = 0
    @State private var signerPubkey: String?
    @State private var cachePath: String?
    @State private var isLoading = true

    var body: some View {
        List {
            // Quick Stats Section
            Section("Quick Stats") {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading stats...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    QuickStatRow(label: "Total Events", value: formatNumber(stats?.totalEvents ?? 0))
                    QuickStatRow(label: "Profiles Cached", value: formatNumber(stats?.databases[.profile]?.count ?? 0))
                    QuickStatRow(label: "Database Size", value: formatBytes(databaseSize))
                    QuickStatRow(label: "Connected Relays", value: "\(relayCount)")
                }
            }

            // Tools Section
            Section("Inspection Tools") {
                NavigationLink(destination: NostrDBStatsView(ndk: ndk)) {
                    ToolRow(icon: "cylinder.split.1x2", title: "NostrDB Stats", subtitle: "Database indexes, event counts, storage", color: .blue)
                }

                NavigationLink(destination: EventInspectorView(ndk: ndk)) {
                    ToolRow(icon: "doc.text.magnifyingglass", title: "Event Inspector", subtitle: "Browse and search cached events", color: .purple)
                }

                NavigationLink(destination: RelayMonitorView(ndk: ndk)) {
                    ToolRow(icon: "antenna.radiowaves.left.and.right", title: "Relay Monitor", subtitle: "Connection states and message counts", color: .green)
                }

                NavigationLink(destination: OutboxInspectorView(ndk: ndk)) {
                    ToolRow(icon: "arrow.left.arrow.right.circle", title: "Outbox Inspector", subtitle: "Relay selection and user tracking", color: .indigo)
                }

                NavigationLink(destination: ProfileManagerInspectorView(ndk: ndk)) {
                    ToolRow(icon: "person.crop.circle.badge.checkmark", title: "Profile Manager", subtitle: "Profile cache and metadata", color: .cyan)
                }

                NavigationLink(destination: ImageCacheInspectorView()) {
                    ToolRow(icon: "photo.stack", title: "Image Cache", subtitle: "Kingfisher memory and disk cache", color: .pink)
                }
            }

            Section("Logging") {
                NavigationLink(destination: LogViewerView()) {
                    ToolRow(icon: "doc.plaintext", title: "Log Viewer", subtitle: "Real-time NDK logs", color: .orange)
                }

                NavigationLink(destination: NetworkTrafficView()) {
                    ToolRow(icon: "arrow.left.arrow.right", title: "Network Traffic", subtitle: "Raw Nostr protocol messages", color: .red)
                }
            }

            // Quick Actions Section
            Section("Quick Actions") {
                Button {
                    Task { await refreshStats() }
                } label: {
                    Label("Refresh Stats", systemImage: "arrow.clockwise")
                }

                if let pubkey = signerPubkey {
                    Button {
                        UIPasteboard.general.string = pubkey
                    } label: {
                        Label("Copy Pubkey", systemImage: "doc.on.doc")
                    }
                }
            }

            // Info Section
            Section("Info") {
                if let path = cachePath {
                    LabeledContent("Cache Path") {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle("Developer Tools")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                await refreshStats()
            }
            .refreshable {
                await refreshStats()
            }
    }

    private func refreshStats() async {
        isLoading = true

        if let cache = ndk.cache as? NDKNostrDBCache {
            stats = cache.getStats()
            databaseSize = cache.getDatabaseSize()
            cachePath = cache.getCachePath()
        } else {
            stats = nil
            databaseSize = 0
            cachePath = nil
        }

        relayCount = await MainActor.run { ndk.relays.count }
        if let signer = ndk.signer {
            signerPubkey = try? await signer.pubkey
        }
        isLoading = false
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000)
        }
        return "\(value)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
