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

    public func startSubscription(muteListManager: MuteListManager) {
        isLoading = true
        error = nil
        videos = []

        let filter = NDKFilter(kinds: videoKinds, limit: 50)

        switch feedMode {
        case .following:
            subscription = ndk.subscribe(
                filter: filter,
                cachePolicy: .cacheWithNetwork
            )

        case let .relay(url):
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
        }

        guard let subscription = subscription else { return }

        subscriptionTask = Task { [weak self] in
            var seenEvents: Set<String> = []

            for await events in subscription.events {
                guard let self = self else { break }
                if Task.isCancelled { break }

                for event in events {
                    guard !seenEvents.contains(event.id) else { continue }
                    seenEvents.insert(event.id)

                    guard !muteListManager.mutedPubkeys.contains(event.pubkey) else {
                        continue
                    }

                    let insertIndex = videos.insertionIndex(for: event) { $0.createdAt > $1.createdAt }
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

    public func switchMode(to mode: FeedMode, muteListManager: MuteListManager) {
        guard mode != feedMode else { return }
        stopSubscription()
        feedMode = mode
        startSubscription(muteListManager: muteListManager)
    }
}
