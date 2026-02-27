import NDKSwiftCore
import SwiftUI

struct RelayConnectionIndicatorButton: View {
    @State private var monitor: RelayConnectionMonitor
    @State private var showDetails = false

    init(ndk: NDK) {
        _monitor = State(initialValue: RelayConnectionMonitor(ndk: ndk))
    }

    var body: some View {
        Button {
            showDetails = true
            logInfo(
                "Relay status indicator tapped",
                category: "Network",
                metadata: [
                    "connected": "\(monitor.connectedCount)",
                    "total": "\(monitor.totalRelays)",
                    "health": monitor.health.label
                ]
            )
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 9, height: 9)

                Text(monitor.statusSummary)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Relay connections \(monitor.health.label)")
        .accessibilityHint("Shows how many relays are currently connected")
        .alert("Relay Connections", isPresented: $showDetails) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage)
        }
        .task {
            await monitor.start()
        }
        .onDisappear {
            monitor.stop()
        }
    }

    private var indicatorColor: Color {
        switch monitor.health {
        case .connected:
            return .green
        case .partial:
            return .orange
        case .connecting:
            return .yellow
        case .disconnected:
            return .gray
        case .failed:
            return .red
        }
    }

    private var statusMessage: String {
        var message = "Status: \(monitor.health.label)\n"
        message += "Connected: \(monitor.connectedCount)/\(monitor.totalRelays)\n"

        if monitor.connectingCount > 0 {
            message += "Connecting: \(monitor.connectingCount)\n"
        }

        if monitor.disconnectedCount > 0 {
            message += "Disconnected: \(monitor.disconnectedCount)\n"
        }

        if monitor.failedCount > 0 {
            message += "Failed: \(monitor.failedCount)\n"
        }

        let listedRelays = monitor.relayStatuses.prefix(5)
        if !listedRelays.isEmpty {
            message += "\n"
            for relay in listedRelays {
                message += "- \(relay.url): \(describe(relay.connectionState))\n"
            }
        }

        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func describe(_ state: NDKRelayConnectionState) -> String {
        switch state {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .authRequired(challenge: _):
            return "auth required"
        case .authenticating:
            return "authenticating"
        case .authenticated:
            return "authenticated"
        case .disconnecting:
            return "disconnecting"
        case .failed(_):
            return "failed"
        }
    }
}
