import Foundation
import NDKSwiftCore
import SwiftUI

@MainActor
@Observable
public final class FeedViewModel {
    private static let loadingTimeout: Duration = .seconds(10)

    public private(set) var posts: [NDKEvent] = []
    public private(set) var isLoading = false
    public var feedMode: FeedMode = .following

    private let ndk: NDK
    private let settings: SettingsManager
    private var subscription: NDKSubscription<NDKEvent>?
    private var subscriptionTask: Task<Void, Never>?
    private var loadingTimeoutTask: Task<Void, Never>?
    private var loadToken = UUID()

    /// Dynamic kinds based on video settings
    private var feedKinds: [Kind] {
        var kinds: [Kind] = [OlasConstants.EventKinds.image]
        if settings.showVideos {
            kinds.append(OlasConstants.EventKinds.shortVideo)
        }
        return kinds
    }

    public init(ndk: NDK, settings: SettingsManager) {
        self.ndk = ndk
        self.settings = settings
    }

    public func startSubscription(muteListManager: MuteListManager) {
        stopSubscription()
        let token = UUID()
        loadToken = token
        isLoading = true
        posts = []

        switch feedMode {
        case .following:
            guard let sessionData = ndk.sessionData,
                  sessionData.contactListState.isAvailable else {
                // Contact list still loading — keep isLoading true, will be triggered by onChange
                return
            }
            let followList = sessionData.followList
            guard !followList.isEmpty else {
                isLoading = false
                return
            }
            var authors = Array(followList)
            if !authors.contains(sessionData.pubkey) {
                authors.append(sessionData.pubkey)
            }
            let filter = NDKFilter(authors: authors, kinds: feedKinds, limit: 50)
            subscription = ndk.subscribe(
                filter: filter,
                cachePolicy: .cacheWithNetwork
            )

        case let .relay(url):
            let filter = NDKFilter(kinds: feedKinds, limit: 50)
            subscription = ndk.subscribe(
                filter: filter,
                cachePolicy: .networkOnly,
                relays: [url],
                exclusiveRelays: true
            )

        case let .pack(pack):
            let filter = NDKFilter(authors: pack.pubkeys, kinds: feedKinds, limit: 100)
            subscription = ndk.subscribe(
                filter: filter,
                cachePolicy: .cacheWithNetwork
            )

        case .network:
            guard let sessionData = ndk.sessionData,
                  sessionData.wotState.isAvailable else {
                // WoT still loading — keep isLoading true, will be triggered by onChange
                return
            }
            let filter = NDKFilter(kinds: feedKinds, limit: 50)
            subscription = ndk.subscribe(
                filter: filter,
                cachePolicy: .cacheWithNetwork
            )

        case let .hashtag(tag):
            var hashtagFilter = NDKFilter(kinds: feedKinds, limit: 50)
            hashtagFilter.addTagFilter("t", values: [tag])
            subscription = ndk.subscribe(
                filter: hashtagFilter,
                cachePolicy: .cacheWithNetwork
            )
        }

        guard let subscription = subscription else {
            isLoading = false
            return
        }

        // Timeout to clear loading state if no events arrive
        loadingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.loadingTimeout)
            guard let self = self, !Task.isCancelled, self.loadToken == token else { return }
            self.isLoading = false
        }

        subscriptionTask = Task { [weak self] in
            var seenEvents: Set<String> = []

            for await events in subscription.events {
                guard let self = self, !Task.isCancelled, self.loadToken == token else { return }

                loadingTimeoutTask?.cancel()
                loadingTimeoutTask = nil

                for event in events {
                    // Track unique events
                    guard !seenEvents.contains(event.id) else { continue }
                    seenEvents.insert(event.id)

                    // Filter muted pubkeys
                    guard !muteListManager.mutedPubkeys.contains(event.pubkey) else {
                        continue
                    }

                    // Filter by WoT for network mode
                    if case .network = self.feedMode,
                       let sessionData = ndk.sessionData,
                       !sessionData.isInWebOfTrust(event.pubkey) {
                        continue
                    }

                    // Insert in sorted position using binary search
                    let insertIndex = posts.insertionIndex(for: event) { $0.createdAt > $1.createdAt }
                    posts.insert(event, at: insertIndex)
                }

                isLoading = false
            }
        }
    }

    public func stopSubscription() {
        loadToken = UUID()
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
        subscriptionTask?.cancel()
        subscriptionTask = nil
        subscription = nil
        isLoading = false
    }

    public func updateForMuteList(_ mutedPubkeys: Set<String>) {
        // Remove muted posts without re-sorting
        posts.removeAll { mutedPubkeys.contains($0.pubkey) }
    }

    public func switchMode(to mode: FeedMode, muteListManager: MuteListManager) {
        guard mode != feedMode else { return }
        stopSubscription()
        feedMode = mode
        startSubscription(muteListManager: muteListManager)
    }
}
