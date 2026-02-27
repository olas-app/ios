import Foundation
import NDKSwiftCore
import Observation

/// Manages the current user's follow packs (creating, editing, deleting)
@MainActor
@Observable
final class FollowPackManager {
    /// User's own follow packs (both generic 39089 and media 39092)
    private(set) var userPacks: [FollowPack] = []

    /// Loading state
    private(set) var isLoading = false

    private let ndk: NDK
    private var userPubkey: String?
    private var subscriptionTask: Task<Void, Never>?

    init(ndk: NDK) {
        self.ndk = ndk
    }

    /// Sets the current user's pubkey and starts loading their packs
    func setUser(_ pubkey: String?) {
        userPubkey = pubkey
        if pubkey != nil {
            loadUserPacks()
        } else {
            userPacks = []
        }
    }

    /// Loads the current user's follow packs
    private func loadUserPacks() {
        subscriptionTask?.cancel()

        guard let pubkey = userPubkey else { return }

        isLoading = true
        subscriptionTask = Task {
            let filter = NDKFilter(
                authors: [pubkey],
                kinds: [OlasConstants.EventKinds.followPack, OlasConstants.EventKinds.mediaFollowPack],
                limit: 50
            )

            let subscription = ndk.subscribeWithTrace(
                filter: filter,
                subscriptionId: "user-packs",
                closeOnEose: true
            )

            var packs: [String: FollowPack] = [:]

            for await events in subscription.events {
                guard !Task.isCancelled else { break }

                for event in events {
                    guard let pack = FollowPack(event: event) else { continue }
                    // Use d-tag as unique identifier, keeping newest version
                    let dTag = event.tags.first { $0.first == "d" }?[safe: 1] ?? event.id
                    if let existing = packs[dTag] {
                        if event.createdAt > existing.event.createdAt {
                            packs[dTag] = pack
                        }
                    } else {
                        packs[dTag] = pack
                    }
                }
            }

            userPacks = packs.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            isLoading = false
        }
    }

    /// Creates a new media follow pack (kind 39092)
    func createPack(
        name: String,
        description: String?,
        image: String?,
        initialMembers: [String] = []
    ) async throws {
        let dTag = generateDTag(from: name)

        _ = try await ndk.publish { builder in
            var b = builder
                .kind(OlasConstants.EventKinds.mediaFollowPack)
                .content(description ?? "")
                .tag(["d", dTag])
                .tag(["title", name])

            if let description, !description.isEmpty {
                b = b.tag(["description", description])
            }

            if let image, !image.isEmpty {
                b = b.tag(["image", image])
            }

            for pubkey in initialMembers {
                b = b.tag(["p", pubkey])
            }

            return b
        }

        // Reload packs to include the new one
        loadUserPacks()
    }

    /// Adds a user to an existing pack
    func addUserToPack(_ userPubkey: String, pack: FollowPack) async throws {
        // Don't add if already in pack
        guard !pack.pubkeys.contains(userPubkey) else { return }

        let updatedPubkeys = pack.pubkeys + [userPubkey]
        try await updatePack(pack, newPubkeys: updatedPubkeys)
    }

    /// Removes a user from a pack
    func removeUserFromPack(_ userPubkey: String, pack: FollowPack) async throws {
        let updatedPubkeys = pack.pubkeys.filter { $0 != userPubkey }
        try await updatePack(pack, newPubkeys: updatedPubkeys)
    }

    /// Updates a pack with new member list
    private func updatePack(_ pack: FollowPack, newPubkeys: [String]) async throws {
        let dTag = pack.event.tags.first { $0.first == "d" }?[safe: 1] ?? pack.id

        _ = try await ndk.publish { builder in
            var b = builder
                .kind(pack.event.kind)
                .content(pack.description ?? "")
                .tag(["d", dTag])
                .tag(["title", pack.name])

            if let description = pack.description, !description.isEmpty {
                b = b.tag(["description", description])
            }

            if let image = pack.image, !image.isEmpty {
                b = b.tag(["image", image])
            }

            for pubkey in newPubkeys {
                b = b.tag(["p", pubkey])
            }

            return b
        }

        // Reload packs
        loadUserPacks()
    }

    /// Deletes a pack by publishing an empty replacement
    func deletePack(_ pack: FollowPack) async throws {
        let dTag = pack.event.tags.first { $0.first == "d" }?[safe: 1] ?? pack.id

        // Publish with no p tags effectively "deletes" it
        _ = try await ndk.publish { builder in
            builder
                .kind(pack.event.kind)
                .content("")
                .tag(["d", dTag])
                .tag(["deleted", "true"])
        }

        loadUserPacks()
    }

    /// Checks if a user is in any of the user's packs
    func packsContaining(_ pubkey: String) -> [FollowPack] {
        userPacks.filter { $0.pubkeys.contains(pubkey) }
    }

    private func generateDTag(from name: String) -> String {
        let slug = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return slug.isEmpty ? UUID().uuidString : slug
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
