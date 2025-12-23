import Foundation

public enum FeedMode: Equatable, Hashable {
    case following
    case relay(url: String)

    var displayName: String {
        switch self {
        case .following:
            return "Following"
        case .relay:
            return "Relay"
        }
    }
}

public enum DiscoveryRelays {
    public static let relays = [
        "wss://relay.olas.app",
        "wss://relay.divine.video",
    ]
}
