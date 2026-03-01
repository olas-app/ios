import Foundation
import NDKSwiftCore
import SwiftUI

@MainActor
@Observable
public final class VideoFeedViewModel {
    public private(set) var videos: [NDKEvent] = []
    public private(set) var isLoading = false
    public private(set) var error: Error?
    public var feedMode: FeedMode = .following

    private let ndk: NDK
    private var subscription: NDKSubscription<NDKEvent>?
    private var subscriptionTask: Task<Void, Never>?

    private let videoKinds: [Kind] = [
        OlasConstants.EventKinds.shortVideo,
        OlasConstants.EventKinds.divineVideo
    ]

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public func startSubscription(muteListManager: MuteListManager, keepExistingVideos: Bool = false) {
        error = nil
        if keepExistingVideos {
            isLoading = videos.isEmpty
        } else {
            isLoading = true
            videos = []
        }

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
            let filter = NDKFilter(authors: authors, kinds: videoKinds, limit: 50)
            subscription = ndk.subscribe(
                filter: filter,
                cachePolicy: .cacheWithNetwork
            )

        case let .relay(url):
            let filter = NDKFilter(kinds: videoKinds, limit: 50)
            subscription = ndk.subscribe(
                filter: filter,
                cachePolicy: .networkOnly,
                relays: [url],
                exclusiveRelays: true
            )

        case let .pack(pack):
            let packFilter = NDKFilter(authors: pack.pubkeys, kinds: videoKinds, limit: 50)
            subscription = ndk.subscribe(
                filter: packFilter,
                cachePolicy: .cacheWithNetwork
            )

        case .network:
            let filter = NDKFilter(kinds: videoKinds, limit: 50)
            subscription = ndk.subscribe(
                filter: filter,
                cachePolicy: .cacheWithNetwork
            )

        case let .hashtag(tag):
            var hashtagFilter = NDKFilter(kinds: videoKinds, limit: 50)
            hashtagFilter.addTagFilter("t", values: [tag])
            subscription = ndk.subscribe(
                filter: hashtagFilter,
                cachePolicy: .cacheWithNetwork
            )
        }

        guard let subscription = subscription else { return }

        subscriptionTask = Task { [weak self] in
            var seenEvents = Set(self?.videos.map(\.id) ?? [])

            for await events in subscription.events {
                guard let self = self else { break }
                if Task.isCancelled { break }

                for event in events {
                    guard !seenEvents.contains(event.id) else { continue }
                    seenEvents.insert(event.id)

                    guard !muteListManager.mutedPubkeys.contains(event.pubkey) else {
                        continue
                    }

                    if case .network = self.feedMode,
                       let sessionData = ndk.sessionData,
                       sessionData.wotState.isAvailable,
                       !sessionData.isInWebOfTrust(event.pubkey) {
                        continue
                    }

                    let insertIndex = videos.diversifiedInsertionIndex(
                        for: event,
                        sortedBy: { $0.createdAt > $1.createdAt },
                        groupKey: \.pubkey
                    )
                    videos.insert(event, at: insertIndex)
                }

                isLoading = false
            }
        }
    }

    public func stopSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        subscription = nil
    }

    public func updateForMuteList(_ mutedPubkeys: Set<String>) {
        videos.removeAll { mutedPubkeys.contains($0.pubkey) }
    }

    public func filterByWoT(_ sessionData: NDKSessionData) {
        guard sessionData.wotState.isAvailable else { return }
        videos.removeAll { !sessionData.isInWebOfTrust($0.pubkey) }
    }

    public func switchMode(to mode: FeedMode, muteListManager: MuteListManager) {
        guard mode != feedMode else { return }
        let previousMode = feedMode
        stopSubscription()
        feedMode = mode

        if previousMode == .following && mode == .network {
            startSubscription(muteListManager: muteListManager, keepExistingVideos: true)
        } else {
            startSubscription(muteListManager: muteListManager)
        }
    }
}
