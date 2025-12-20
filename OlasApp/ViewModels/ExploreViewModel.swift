import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

/// ViewModel for ExploreView that handles search and content discovery
@MainActor
@Observable
class ExploreViewModel {
    // MARK: - Published State

    var searchText = ""
    var searchResults: [NDKEvent] = []
    var userResults: [SearchUserResult] = []
    var trendingPosts: [NDKEvent] = []
    var suggestedUsers: [SuggestedUser] = []
    var selectedTab: ExploreTab = .forYou

    // MARK: - Private State

    private let ndk: NDK
    private let settings: SettingsManager
    private let muteListManager: MuteListManager
    private var seenPubkeys: Set<String> = []
    private var searchTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var filteredTrendingPosts: [NDKEvent] {
        filterMuted(trendingPosts)
    }

    var filteredSuggestedUsers: [SuggestedUser] {
        suggestedUsers.filter { !muteListManager.isMuted($0.pubkey) }
    }

    var filteredSearchResults: [NDKEvent] {
        filterMuted(searchResults)
    }

    var filteredUserResults: [SearchUserResult] {
        userResults.filter { !muteListManager.isMuted($0.pubkey) }
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

    /// Loads trending/discover content
    func loadDiscoverContent() async {
        let filter = NDKFilter(
            kinds: feedKinds,
            limit: 50
        )

        let subscription = ndk.subscribe(filter: filter)

        for await events in subscription.events {
            insertTrendingPostsBatch(events)
        }
    }

    private func insertTrendingPostsBatch(_ newPosts: [NDKEvent]) {
        // Combine and sort - more efficient than individual inserts
        let combined = trendingPosts + newPosts
        trendingPosts = combined.sorted { $0.createdAt > $1.createdAt }

        // Extract suggested users
        for event in newPosts {
            if !seenPubkeys.contains(event.pubkey), suggestedUsers.count < 10 {
                seenPubkeys.insert(event.pubkey)
                suggestedUsers.append(SuggestedUser(pubkey: event.pubkey))
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

        searchTask = Task {
            await clearSearchResults()
            await searchUsers(query: query)
            await searchPosts(query: query)
        }
    }

    private func searchUsers(query: String) async {
        if query.hasPrefix("npub") {
            await searchByNpub(query)
        } else {
            await searchUsersByName(query)
        }
    }

    private func searchByNpub(_ npub: String) async {
        guard let user = try? NDKUser(npub: npub, ndk: ndk) else { return }
        userResults = [SearchUserResult(pubkey: user.pubkey)]
    }

    private func searchUsersByName(_ query: String) async {
        let filter = NDKFilter(
            kinds: [EventKind.metadata],
            limit: 50
        )

        let subscription = ndk.subscribe(filter: filter)

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

    private func searchPosts(query: String) async {
        let filter = NDKFilter(
            kinds: feedKinds,
            limit: 50
        )

        let subscription = ndk.subscribe(filter: filter)

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

struct SuggestedUser: Identifiable {
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
