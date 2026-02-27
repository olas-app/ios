import Foundation
import NDKSwiftCore
import Observation

/// Observable state for managing repost interactions on an event
///
/// Tracks repost count, whether the current user has reposted, and provides
/// methods to toggle repost state or create quote reposts.
@Observable
@MainActor
public final class RepostState {
    // MARK: - Public Properties

    /// Number of unique users who have reposted or quoted this event
    public private(set) var count: Int = 0

    /// Whether the current user has reposted this event
    public private(set) var hasReposted: Bool = false

    /// Pubkeys of users who have reposted (for showing avatars, etc.)
    public private(set) var pubkeys: [String] = []

    // MARK: - Private Properties

    private let ndk: NDK
    private let event: NDKEvent
    private var userRepostEvent: NDKEvent?
    @ObservationIgnored nonisolated(unsafe) private var observationTask: Task<Void, Never>?

    /// Maximum reposts to track to prevent unbounded memory growth
    private let maxReposts = 500

    // MARK: - Initialization

    /// Create a new RepostState for tracking reposts on an event
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - event: The event to track reposts for
    public init(ndk: NDK, event: NDKEvent) {
        self.ndk = ndk
        self.event = event
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Public Methods

    /// Start observing repost events for this event
    public func start() async {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            await self?.observeReposts()
        }
    }

    /// Stop observing reposts
    public func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Toggle repost state - creates a repost if not reposted, deletes if already reposted
    public func toggle() async throws {
        guard ndk.signer != nil else {
            throw RepostError.noSigner
        }

        if hasReposted, let userRepostEvent {
            // Delete existing repost
            try await userRepostEvent.delete(signer: ndk.signer!, ndk: ndk)
            self.userRepostEvent = nil
            hasReposted = false
        } else {
            // Create new repost
            let repostEvent = try await ndk.repost(event)
            userRepostEvent = repostEvent
            hasReposted = true
        }
    }

    /// Create a quote repost with the given content
    /// - Parameter content: The quote content
    /// - Returns: The created quote event
    @discardableResult
    public func quote(content: String) async throws -> NDKEvent {
        guard ndk.signer != nil else {
            throw RepostError.noSigner
        }

        let quoteEvent = try await ndk.quoteRepost(event, comment: content)
        // If user hadn't reposted before, this counts as their repost now
        if !hasReposted {
            userRepostEvent = quoteEvent
            hasReposted = true
        }
        return quoteEvent
    }

    // MARK: - Private Methods

    private func observeReposts() async {
        // Subscribe to reposts and generic reposts using proper tagging for replaceable events
        let repostFilter = NDKFilter.tagging(event, kinds: [6, 16])

        // Create subscription
        let repostSub = ndk.subscribeWithTrace(
            filter: repostFilter,
            maxAge: 0,
            cachePolicy: .cacheWithNetwork,
            closeOnEose: false
        )

        // Track all repost events by ID to handle updates
        var allReposts: [String: NDKEvent] = [:]

        for await batch in repostSub.events {
            guard !Task.isCancelled else { break }
            for event in batch {
                allReposts[event.id] = event
            }

            // Prune if over limit - keep most recent by created_at
            if allReposts.count > maxReposts {
                let sorted = allReposts.values.sorted { $0.createdAt > $1.createdAt }
                allReposts = Dictionary(
                    uniqueKeysWithValues: sorted.prefix(maxReposts).map { ($0.id, $0) }
                )
            }

            await updateState(from: Array(allReposts.values))
        }
    }

    private func updateState(from events: [NDKEvent]) async {
        let userPubkey = try? await ndk.signer?.pubkey

        // Count unique pubkeys
        var uniquePubkeys = Set<String>()
        var foundUserRepost: NDKEvent?

        for event in events {
            uniquePubkeys.insert(event.pubkey)

            if let userPubkey, event.pubkey == userPubkey {
                foundUserRepost = event
            }
        }

        count = uniquePubkeys.count
        pubkeys = Array(uniquePubkeys)
        hasReposted = foundUserRepost != nil
        userRepostEvent = foundUserRepost
    }
}

// MARK: - Errors

public enum RepostError: Error, LocalizedError {
    case noSigner

    public var errorDescription: String? {
        switch self {
        case .noSigner:
            return "No signer available. User must be logged in to repost."
        }
    }
}
