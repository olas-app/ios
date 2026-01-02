import Foundation
import NDKSwiftCore

struct FollowPack: Identifiable, Hashable, Sendable {
    static func == (lhs: FollowPack, rhs: FollowPack) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let id: String
    let event: NDKEvent
    let name: String
    let description: String?
    let image: String?
    let pubkeys: [String]
    let creatorPubkey: String

    init?(event: NDKEvent) {
        guard event.kind == OlasConstants.EventKinds.followPack ||
              event.kind == OlasConstants.EventKinds.mediaFollowPack else {
            return nil
        }

        self.id = event.id
        self.event = event
        self.creatorPubkey = event.pubkey

        // Extract name from "title" tag first, fallback to "d" tag
        if let titleTag = event.tags.first(where: { $0.first == "title" }),
           titleTag.count > 1, !titleTag[1].isEmpty {
            self.name = titleTag[1]
        } else if let dTag = event.tags.first(where: { $0.first == "d" }),
                  dTag.count > 1, !dTag[1].isEmpty {
            self.name = dTag[1]
        } else {
            return nil
        }

        // Extract description from "description" tag or content
        if let descTag = event.tags.first(where: { $0.first == "description" }),
           descTag.count > 1 {
            self.description = descTag[1]
        } else if !event.content.isEmpty {
            self.description = event.content
        } else {
            self.description = nil
        }

        // Extract image from "image" tag
        if let imageTag = event.tags.first(where: { $0.first == "image" }),
           imageTag.count > 1 {
            self.image = imageTag[1]
        } else {
            self.image = nil
        }

        // Extract pubkeys from "p" tags
        self.pubkeys = event.tags
            .filter { $0.first == "p" && $0.count > 1 }
            .compactMap { $0[1] }
    }

    var memberCount: Int {
        pubkeys.count
    }
}
