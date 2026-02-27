import Foundation
import NDKSwiftCore

extension NDK {
    /// Wrapper around `subscribe` that emits a trace log whenever a subscription is created.
    func subscribeWithTrace(
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        exclusiveRelays: Bool = false,
        subscriptionId: String? = nil,
        closeOnEose: Bool? = nil,
        includeRelayUpdates: Bool = false
    ) -> NDKSubscription<NDKEvent> {
        let generatedID = "auto-\(UUID().uuidString.prefix(8))"
        let traceID = subscriptionId ?? generatedID

        logInfo(
            "Creating subscription",
            category: "Network",
            metadata: [
                "subscriptionId": traceID,
                "filter": filter.description,
                "cachePolicy": String(describing: cachePolicy),
                "maxAge": String(format: "%.1f", maxAge),
                "exclusiveRelays": exclusiveRelays.description,
                "closeOnEose": String(closeOnEose ?? (maxAge > 0)),
                "relayCount": "\(relays?.count ?? 0)"
            ]
        )

        return subscribe(
            filter: filter,
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: relays,
            exclusiveRelays: exclusiveRelays,
            subscriptionId: subscriptionId,
            closeOnEose: closeOnEose,
            includeRelayUpdates: includeRelayUpdates
        )
    }

    /// Wrapper for the options-based subscription API.
    func subscribeWithTrace(
        filter: NDKFilter,
        options: NDKSubscriptionOptions? = nil,
        includeRelayUpdates: Bool = false
    ) -> NDKSubscription<NDKEvent> {
        logInfo(
            "Creating subscription",
            category: "Network",
            metadata: [
                "subscriptionId": "options-api",
                "filter": filter.description,
                "options": String(describing: options ?? .default)
            ]
        )

        return subscribe(
            filter: filter,
            options: options,
            includeRelayUpdates: includeRelayUpdates
        )
    }
}
