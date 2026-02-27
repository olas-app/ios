import NDKSwiftCore
import NDKSwiftUI
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.olas.app", category: "ExplorePagination")

/// ViewModel for ExploreView that handles search and content discovery
@MainActor
@Observable
class ExploreViewModel {
    // MARK: - Published State

    var searchText = ""
    var searchResults: [NDKEvent] = []
    var userResults: [SearchUserResult] = []
    var hashtagResults: [NDKEvent] = []
    var trendingPosts: [NDKEvent] = []
    var followPacks: [FollowPack] = []
    var selectedTab: ExploreTab = .forYou

    // MARK: - Private State

    private let ndk: NDK
    private let settings: SettingsManager
    private let muteListManager: MuteListManager
    private var searchTask: Task<Void, Never>?
    private var isLoadingMore = false
    private var seenEventIds: Set<String> = []

    // MARK: - Computed Properties

    var filteredTrendingPosts: [NDKEvent] {
        filterMuted(trendingPosts)
    }

    var filteredSearchResults: [NDKEvent] {
        filterMuted(searchResults)
    }

    var filteredUserResults: [SearchUserResult] {
        userResults.filter { !muteListManager.isMuted($0.pubkey) }
    }

    var filteredHashtagResults: [NDKEvent] {
        filterMuted(hashtagResults)
    }

    /// Returns the lowercase tag if searchText starts with `#` and has >1 char, else nil
    var activeHashtagSearch: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#"), trimmed.count > 1 else { return nil }
        return String(trimmed.dropFirst()).lowercased()
    }

    var featuredPacks: [FollowPack] {
        Array(followPacks.prefix(5))
    }

    private var feedKinds: [Kind] {
        var kinds: [Kind] = [OlasConstants.EventKinds.image]
        if settings.showVideos {
            kinds.append(OlasConstants.EventKinds.shortVideo)
        }
        return kinds
    }

    // MARK: - Initialization

    init(ndk: NDK, settings: SettingsManager, muteListManager: MuteListManager) {
        self.ndk = ndk
        self.settings = settings
        self.muteListManager = muteListManager
    }

    // MARK: - Content Discovery

    /// Loads trending/discover content and follow packs
    func loadDiscoverContent() async {
        // Load packs and posts concurrently
        async let packsTask: Void = loadFollowPacks()
        async let postsTask: Void = loadTrendingPosts()
        _ = await (packsTask, postsTask)
    }

    private func loadTrendingPosts() async {
        await fetchPosts(until: nil)
    }

    private func fetchPosts(until: Timestamp?) async {
        logger.info("fetchPosts called — until: \(until.map { String($0) } ?? "nil", privacy: .public), current total: \(self.trendingPosts.count)")

        let filter = NDKFilter(
            kinds: feedKinds,
            until: until,
            limit: 50
        )

        let subscription = ndk.subscribeWithTrace(
            filter: filter,
            closeOnEose: true
        )

        var batchCount = 0
        for await events in subscription.events {
            batchCount += 1
            let newEvents = events.filter { seenEventIds.insert($0.id).inserted }
            logger.info("fetchPosts batch #\(batchCount): received \(events.count) events, \(newEvents.count) new (after dedup)")
            guard !newEvents.isEmpty else { continue }
            let combined = trendingPosts + newEvents
            trendingPosts = combined.sorted { $0.createdAt > $1.createdAt }
            logger.info("fetchPosts total now: \(self.trendingPosts.count), filtered: \(self.filteredTrendingPosts.count)")
        }
        logger.info("fetchPosts subscription ended — total batches: \(batchCount), final count: \(self.trendingPosts.count)")
    }

    /// Called by PostGridView when a cell near the end of the displayed list appears
    func loadMoreIfNeeded() {
        guard !isLoadingMore else {
            logger.debug("loadMoreIfNeeded: already loading, skipping")
            return
        }

        isLoadingMore = true
        let oldestTimestamp = trendingPosts.last?.createdAt
        logger.info("loadMoreIfNeeded: TRIGGERED — loading more, oldest timestamp: \(oldestTimestamp.map { String($0) } ?? "nil", privacy: .public)")

        Task {
            defer { isLoadingMore = false }
            guard let until = oldestTimestamp else {
                logger.warning("loadMoreIfNeeded: no oldest timestamp, aborting")
                return
            }
            await fetchPosts(until: until - 1)
        }
    }

    private func loadFollowPacks() async {
        // Prioritize media packs (39092) by requesting them first, then generic (39089)
        let subscription = ndk.subscribeWithTrace(
            filter: NDKFilter(
                kinds: [OlasConstants.EventKinds.mediaFollowPack, OlasConstants.EventKinds.followPack],
                limit: 30
            ),
            subscriptionId: "explore-packs",
            closeOnEose: true
        )

        var discovered: [String: FollowPack] = [:]

        for await batch in subscription.events {
            for event in batch {
                guard let pack = FollowPack(event: event) else { continue }
                guard pack.memberCount > 0 else { continue }

                // Dedupe by name - prefer media packs over generic packs
                let key = pack.name.lowercased()
                if let existing = discovered[key] {
                    let existingIsMedia = existing.event.kind == OlasConstants.EventKinds.mediaFollowPack
                    let newIsMedia = event.kind == OlasConstants.EventKinds.mediaFollowPack

                    // Keep media pack over generic, or keep one with more members if same type
                    if newIsMedia && !existingIsMedia {
                        discovered[key] = pack
                    } else if newIsMedia == existingIsMedia && pack.memberCount > existing.memberCount {
                        discovered[key] = pack
                    }
                } else {
                    discovered[key] = pack
                }
            }

            // Sort: media packs first, then by member count
            followPacks = discovered.values.sorted { pack1, pack2 in
                let pack1IsMedia = pack1.event.kind == OlasConstants.EventKinds.mediaFollowPack
                let pack2IsMedia = pack2.event.kind == OlasConstants.EventKinds.mediaFollowPack

                if pack1IsMedia != pack2IsMedia {
                    return pack1IsMedia // Media packs come first
                }
                return pack1.memberCount > pack2.memberCount
            }
        }
    }

    // MARK: - Search

    /// Performs search for users and posts
    func performSearch(query: String) async {
        // Cancel previous search
        searchTask?.cancel()

        guard !query.isEmpty else {
            clearSearchResults()
            return
        }

        // Route hashtag queries to tag-based search
        if let tag = activeHashtagSearch {
            searchTask = Task {
                await clearSearchResults()
                await searchByHashtag(tag)
            }
            return
        }

        searchTask = Task {
            await clearSearchResults()
            await searchUsers(query: query)
            await searchPosts(query: query)
        }
    }

    private func searchUsers(query: String) async {
        if query.hasPrefix("npub") {
            await searchByNpub(query)
            return
        }

        // Run NIP-05 check and name search in parallel if it looks like a domain
        if looksLikeDomain(query) {
            async let nip05Result: Void = tryNip05Resolution(query)
            async let nameResult: Void = searchUsersByName(query)
            _ = await (nip05Result, nameResult)
        } else {
            await searchUsersByName(query)
        }
    }

    private func looksLikeDomain(_ query: String) -> Bool {
        // Has @ with domain, or bare domain like "dergigi.com"
        if query.contains("@") {
            let parts = query.split(separator: "@")
            guard parts.count == 2 else { return false }
            return String(parts[1]).contains(".")
        }
        return query.contains(".") && !query.contains(" ")
    }

    private func tryNip05Resolution(_ query: String) async {
        let nip05 = query.contains("@") ? query : "_@\(query)"
        guard let pubkey = await resolveNip05(nip05) else { return }
        // Add to results if not already present
        if !userResults.contains(where: { $0.pubkey == pubkey }) {
            userResults.insert(SearchUserResult(pubkey: pubkey), at: 0)
        }
    }

    private func resolveNip05(_ identifier: String) async -> String? {
        let parts = identifier.split(separator: "@")
        guard parts.count == 2 else { return nil }

        let name = String(parts[0])
        let domain = String(parts[1])

        guard let url = URL(string: "https://\(domain)/.well-known/nostr.json?name=\(name)") else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let names = json["names"] as? [String: String],
                  let pubkey = names[name]
            else {
                return nil
            }
            return pubkey
        } catch {
            return nil
        }
    }

    private func searchByNpub(_ npub: String) async {
        guard let pubkey = try? Bech32.pubkey(from: npub) else { return }
        userResults = [SearchUserResult(pubkey: pubkey)]
    }

    private func searchUsersByName(_ query: String) async {
        let filter = NDKFilter(
            kinds: [EventKind.metadata],
            limit: 50
        )

        let subscription = ndk.subscribeWithTrace(filter: filter)

        for await events in subscription.events {
            guard !Task.isCancelled else { break }

            for event in events {
                if let metadata = parseUserMetadata(from: event.content),
                   metadata.matchesQuery(query)
                {
                    userResults.append(SearchUserResult(pubkey: event.pubkey))
                }
            }
        }
    }

    private func searchByHashtag(_ tag: String) async {
        var filter = NDKFilter(kinds: feedKinds, limit: 50)
        filter.addTagFilter("t", values: [tag])

        let subscription = ndk.subscribeWithTrace(
            filter: filter,
            closeOnEose: true
        )

        for await events in subscription.events {
            guard !Task.isCancelled else { break }

            let newEvents = events.filter { !muteListManager.isMuted($0.pubkey) }
            let combined = hashtagResults + newEvents
            hashtagResults = combined.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func searchPosts(query: String) async {
        let filter = NDKFilter(
            kinds: feedKinds,
            limit: 50
        )

        let subscription = ndk.subscribeWithTrace(filter: filter)

        for await events in subscription.events {
            guard !Task.isCancelled else { break }

            for event in events {
                if event.content.localizedCaseInsensitiveContains(query) {
                    searchResults.append(event)
                }
            }
        }
    }

    /// Clears search text and results
    func clearSearch() {
        searchText = ""
        clearSearchResults()
    }

    private func clearSearchResults() {
        searchResults = []
        userResults = []
        hashtagResults = []
    }

    // MARK: - Helper Methods

    private func filterMuted(_ events: [NDKEvent]) -> [NDKEvent] {
        events.filter { !muteListManager.isMuted($0.pubkey) }
    }

    private func parseUserMetadata(from jsonString: String) -> UserMetadata? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let displayName = json["display_name"] as? String ?? json["displayName"] as? String
        let name = json["name"] as? String

        return UserMetadata(displayName: displayName, name: name)
    }
}

// MARK: - Supporting Types

enum ExploreTab: String, CaseIterable {
    case forYou = "For You"
    case trending = "Trending"
    case recent = "Recent"
}

struct SearchUserResult: Identifiable {
    let id = UUID()
    let pubkey: String
}

/// Parsed user metadata for search
private struct UserMetadata {
    let displayName: String?
    let name: String?

    var searchableName: String {
        displayName ?? name ?? ""
    }

    func matchesQuery(_ query: String) -> Bool {
        searchableName.localizedCaseInsensitiveContains(query)
    }
}
