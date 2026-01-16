import Foundation
import NDKSwiftCore
import Observation

/// Observable state for managing reaction interactions on an event
///
/// Tracks reaction count, whether the current user has reacted, and provides
/// methods to toggle reaction state.
@Observable
@MainActor
public final class ReactionState {
    // MARK: - Public Properties

    /// Number of unique users who have reacted with this emoji
    public private(set) var count: Int = 0

    /// Whether the current user has reacted with this emoji
    public private(set) var hasReacted: Bool = false

    /// Pubkeys of users who have reacted (for showing avatars, etc.)
    public private(set) var pubkeys: [String] = []

    // MARK: - Private Properties

    private let ndk: NDK
    private let event: NDKEvent
    private let reaction: String
    private var userReactionEvent: NDKEvent?
    @ObservationIgnored nonisolated(unsafe) private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var activeSubscription: NDKSubscription<NDKEvent>?

    /// Maximum reactions to track to prevent unbounded memory growth
    private let maxReactions = 500

    // MARK: - Initialization

    /// Create a new ReactionState for tracking reactions on an event
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - event: The event to track reactions for
    ///   - reaction: The reaction emoji to track (default: "+")
    public init(ndk: NDK, event: NDKEvent, reaction: String = "+") {
        self.ndk = ndk
        self.event = event
        self.reaction = reaction
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Public Methods

    /// Start observing reaction events for this event
    public func start() async {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            await self?.observeReactions()
        }
    }

    /// Stop observing reactions
    public func stop() {
        observationTask?.cancel()
        observationTask = nil
        activeSubscription?.close()
        activeSubscription = nil
    }

    /// Toggle reaction state - creates a reaction if not reacted, deletes if already reacted
    public func toggle() async throws {
        guard ndk.signer != nil else {
            throw ReactionError.noSigner
        }

        if hasReacted, let userReactionEvent {
            // Delete existing reaction
            try await userReactionEvent.delete(signer: ndk.signer!, ndk: ndk)
            self.userReactionEvent = nil
            hasReacted = false
        } else {
            // Create new reaction
            let reactionEvent = try await ndk.react(to: event, with: reaction)
            userReactionEvent = reactionEvent
            hasReacted = true
        }
    }

    // MARK: - Private Methods

    private func observeReactions() async {
        let filter = NDKFilter.tagging(event, kinds: [OlasConstants.EventKinds.reaction])

        let subscription = ndk.subscribe(
            filter: filter,
            maxAge: 0,
            cachePolicy: .cacheWithNetwork,
            closeOnEose: false
        )

        // Store subscription reference for cleanup
        self.activeSubscription = subscription

        var allReactions: [String: NDKEvent] = [:]

        for await batch in subscription.events {
            // Check for task cancellation
            guard !Task.isCancelled else { break }

            for event in batch {
                allReactions[event.id] = event
            }

            // Prune if over limit - keep most recent by created_at
            if allReactions.count > maxReactions {
                let sorted = allReactions.values.sorted { $0.createdAt > $1.createdAt }
                allReactions = Dictionary(
                    uniqueKeysWithValues: sorted.prefix(maxReactions).map { ($0.id, $0) }
                )
            }

            await updateState(from: Array(allReactions.values))
        }
    }

    private func updateState(from events: [NDKEvent]) async {
        let userPubkey = try? await ndk.signer?.pubkey

        // Filter to only reactions matching our emoji (or "+" for likes)
        let matchingReactions = events.filter { event in
            event.content == reaction || (reaction == "+" && event.content.isEmpty)
        }

        var uniquePubkeys = Set<String>()
        var foundUserReaction: NDKEvent?

        for event in matchingReactions {
            uniquePubkeys.insert(event.pubkey)

            if let userPubkey, event.pubkey == userPubkey {
                foundUserReaction = event
            }
        }

        count = uniquePubkeys.count
        pubkeys = Array(uniquePubkeys)
        hasReacted = foundUserReaction != nil
        userReactionEvent = foundUserReaction
    }
}

// MARK: - Errors

public enum ReactionError: Error, LocalizedError {
    case noSigner

    public var errorDescription: String? {
        switch self {
        case .noSigner:
            return "No signer available. User must be logged in to react."
        }
    }
}
