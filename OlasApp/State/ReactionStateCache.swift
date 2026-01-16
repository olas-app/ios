import Foundation
import NDKSwiftCore

/// A cache for sharing ReactionState instances across views
///
/// Instead of each LikeButton creating its own ReactionState, they share
/// instances through this cache. When a view disappears and releases its
/// reference, the weak reference in the cache allows the state to be deallocated.
@MainActor
public final class ReactionStateCache {
    public static let shared = ReactionStateCache()

    private var cache: [String: WeakRef<ReactionState>] = [:]
    private let maxCacheSize = 100

    private init() {}

    /// Get or create a ReactionState for an event
    /// - Parameters:
    ///   - event: The event to track reactions for
    ///   - ndk: The NDK instance
    ///   - reaction: The reaction emoji (default: "+")
    /// - Returns: A shared or new ReactionState instance
    public func state(for event: NDKEvent, ndk: NDK, reaction: String = "+") -> ReactionState {
        let key = "\(event.id)-\(reaction)"

        // Return existing if available and still alive
        if let existing = cache[key]?.value {
            return existing
        }

        // Create new state
        let state = ReactionState(ndk: ndk, event: event, reaction: reaction)
        cache[key] = WeakRef(state)

        // Prune cache if too large
        if cache.count > maxCacheSize {
            pruneCache()
        }

        return state
    }

    /// Remove a specific state from cache (call when view disappears)
    public func remove(for eventId: String, reaction: String = "+") {
        let key = "\(eventId)-\(reaction)"
        if let ref = cache[key], ref.value == nil {
            cache.removeValue(forKey: key)
        }
    }

    /// Prune the cache by removing nil weak references
    private func pruneCache() {
        cache = cache.filter { $0.value.value != nil }
    }

    /// Clear all cached states
    public func clear() {
        cache.removeAll()
    }
}

/// A weak reference wrapper
private final class WeakRef<T: AnyObject> {
    weak var value: T?

    init(_ value: T) {
        self.value = value
    }
}
