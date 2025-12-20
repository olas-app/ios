import Foundation
import NDKSwiftCore
import SwiftUI

@MainActor
@Observable
public final class FeedViewModel {
    public private(set) var posts: [NDKEvent] = []
    public private(set) var isLoading = false
    public private(set) var error: Error?
    public var feedMode: FeedMode = .following

    private let ndk: NDK
    private let settings: SettingsManager
    private var subscription: NDKSubscription<NDKEvent>?
    private var subscriptionTask: Task<Void, Never>?
    private var allPosts: [NDKEvent] = []
    private var currentMuteListManager: MuteListManager?

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
        currentMuteListManager = muteListManager
        isLoading = true
        error = nil
        posts = []
        allPosts = []

        let filter = NDKFilter(kinds: feedKinds, limit: 50)

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
        }

        guard let subscription = subscription else { return }

        subscriptionTask = Task { [weak self] in
            var seenEvents: Set<String> = []

            for await events in subscription.events {
                guard let self = self else { break }
                if Task.isCancelled { break }

                for event in events {
                    // Track unique events
                    guard !seenEvents.contains(event.id) else { continue }
                    seenEvents.insert(event.id)

                    // Filter muted pubkeys
                    guard !muteListManager.mutedPubkeys.contains(event.pubkey) else {
                        continue
                    }

                    // Add to allPosts for tracking
                    allPosts.append(event)

                    // Insert in sorted position using binary search
                    let insertIndex = posts.insertionIndex(for: event) { $0.createdAt > $1.createdAt }
                    posts.insert(event, at: insertIndex)
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
        // Remove muted posts without re-sorting
        posts.removeAll { mutedPubkeys.contains($0.pubkey) }
        allPosts.removeAll { mutedPubkeys.contains($0.pubkey) }
    }

    public func switchMode(to mode: FeedMode, muteListManager: MuteListManager) {
        guard mode != feedMode else { return }
        stopSubscription()
        feedMode = mode
        startSubscription(muteListManager: muteListManager)
    }
}
