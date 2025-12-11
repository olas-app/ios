import Foundation
import SwiftUI
import NDKSwiftCore

@MainActor
public final class FeedViewModel: ObservableObject {
    @Published public private(set) var posts: [NDKEvent] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    @Published public var feedMode: FeedMode = .following

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

        let filter = NDKFilter(kinds: feedKinds, limit: 50)

        switch feedMode {
        case .following:
            subscription = ndk.subscribe(
                filter: filter,
                cachePolicy: .cacheWithNetwork
            )

        case .relay(let url):
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

            for await event in subscription.events {
                guard let self = self else { break }
                if Task.isCancelled { break }

                // Track unique events
                guard !seenEvents.contains(event.id) else { continue }
                seenEvents.insert(event.id)

                // Add to allPosts
                allPosts.append(event)

                // Filter and sort posts
                posts = allPosts
                    .filter { !muteListManager.mutedPubkeys.contains($0.pubkey) }
                    .sorted { $0.createdAt > $1.createdAt }

                isLoading = false
            }
        }
    }

    public func stopSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        subscription = nil
    }

    public func switchMode(to mode: FeedMode, muteListManager: MuteListManager) {
        guard mode != feedMode else { return }
        stopSubscription()
        feedMode = mode
        startSubscription(muteListManager: muteListManager)
    }
}
