import Foundation

public enum FeedMode: Equatable, Hashable {
    case following
    case relay(url: String)
    case pack(SavedPack)
    case hashtag(String)

    var displayName: String {
        switch self {
        case .following:
            return "Following"
        case .relay:
            return "Relay"
        case .pack(let pack):
            return pack.name
        case .hashtag(let tag):
            return "#\(tag)"
        }
    }
}

public enum DiscoveryRelays {
    public static let relays = [
        "wss://relay.olas.app",
        "wss://relay.divine.video",
    ]
}

// MARK: - Saved Pack

/// A serializable version of FollowPack for persistence
public struct SavedPack: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let image: String?
    public let pubkeys: [String]
    public let creatorPubkey: String

    public var memberCount: Int { pubkeys.count }

    init(from pack: FollowPack) {
        self.id = pack.id
        self.name = pack.name
        self.description = pack.description
        self.image = pack.image
        self.pubkeys = pack.pubkeys
        self.creatorPubkey = pack.creatorPubkey
    }
}

// MARK: - Codable Conformance for FeedMode

extension FeedMode: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, relayURL, pack, hashtag
    }

    private enum FeedType: String, Codable {
        case following, relay, pack, hashtag
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(FeedType.self, forKey: .type)

        switch type {
        case .following:
            self = .following
        case .relay:
            let url = try container.decode(String.self, forKey: .relayURL)
            self = .relay(url: url)
        case .pack:
            let pack = try container.decode(SavedPack.self, forKey: .pack)
            self = .pack(pack)
        case .hashtag:
            let tag = try container.decode(String.self, forKey: .hashtag)
            self = .hashtag(tag)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .following:
            try container.encode(FeedType.following, forKey: .type)
        case .relay(let url):
            try container.encode(FeedType.relay, forKey: .type)
            try container.encode(url, forKey: .relayURL)
        case .pack(let pack):
            try container.encode(FeedType.pack, forKey: .type)
            try container.encode(pack, forKey: .pack)
        case .hashtag(let tag):
            try container.encode(FeedType.hashtag, forKey: .type)
            try container.encode(tag, forKey: .hashtag)
        }
    }
}
