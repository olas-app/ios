import Foundation
import NDKSwiftCore
import Observation

@MainActor
@Observable
final class RelayConnectionMonitor {
    enum Health {
        case connected
        case partial
        case connecting
        case disconnected
        case failed

        var label: String {
            switch self {
            case .connected:
                return "Connected"
            case .partial:
                return "Partially Connected"
            case .connecting:
                return "Connecting"
            case .disconnected:
                return "Disconnected"
            case .failed:
                return "Connection Failed"
            }
        }
    }

    struct RelayStatus: Identifiable {
        let url: RelayURL
        let connectionState: NDKRelayConnectionState

        var id: RelayURL { url }
    }

    private let ndk: NDK
    private var relayStates: [RelayURL: NDKRelayConnectionState] = [:]
    private var relayStateTasks: [RelayURL: Task<Void, Never>] = [:]
    private var relayRefreshTask: Task<Void, Never>?
    private var isStarted = false

    var totalRelays: Int {
        relayStates.count
    }

    var connectedCount: Int {
        relayStates.values.filter { state in
            state == .connected || state == .authenticated
        }.count
    }

    var connectingCount: Int {
        relayStates.values.filter { state in
            state == .connecting || state == .authenticating
        }.count
    }

    var failedCount: Int {
        relayStates.values.filter { state in
            if case .failed = state {
                return true
            }
            return false
        }.count
    }

    var disconnectedCount: Int {
        relayStates.values.filter { state in
            switch state {
            case .disconnected, .disconnecting, .authRequired(challenge: _):
                return true
            default:
                return false
            }
        }.count
    }

    var health: Health {
        guard totalRelays > 0 else {
            return .disconnected
        }

        if connectedCount == totalRelays {
            return .connected
        }

        if connectedCount > 0 {
            return .partial
        }

        if connectingCount > 0 {
            return .connecting
        }

        if failedCount > 0 {
            return .failed
        }

        return .disconnected
    }

    var statusSummary: String {
        "\(connectedCount)/\(totalRelays)"
    }

    var relayStatuses: [RelayStatus] {
        relayStates
            .map { RelayStatus(url: $0.key, connectionState: $0.value) }
            .sorted { left, right in
                left.url < right.url
            }
    }

    init(ndk: NDK) {
        self.ndk = ndk
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true

        await syncRelayMonitors()

        relayRefreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await self.syncRelayMonitors()
            }
        }
    }

    func stop() {
        relayRefreshTask?.cancel()
        relayRefreshTask = nil

        for task in relayStateTasks.values {
            task.cancel()
        }
        relayStateTasks.removeAll()

        isStarted = false
    }

    private func syncRelayMonitors() async {
        let relays = await ndk.relays
        let relayURLs = Set(relays.map(\.url))

        // Stop monitors for relays no longer present.
        for (relayURL, task) in relayStateTasks where !relayURLs.contains(relayURL) {
            task.cancel()
            relayStateTasks.removeValue(forKey: relayURL)
            relayStates.removeValue(forKey: relayURL)
        }

        // Start monitors for newly discovered relays.
        for relay in relays where relayStateTasks[relay.url] == nil {
            let currentState = await relay.connectionState
            relayStates[relay.url] = currentState

            relayStateTasks[relay.url] = Task { [weak self, relay] in
                guard let self else { return }
                for await state in relay.stateStream {
                    if Task.isCancelled { return }
                    await self.handleStateUpdate(for: relay.url, state: state.connectionState)
                }
            }
        }
    }

    private func handleStateUpdate(for relayURL: RelayURL, state: NDKRelayConnectionState) {
        let previousState = relayStates[relayURL]
        guard previousState != state else { return }

        relayStates[relayURL] = state
    }

}
