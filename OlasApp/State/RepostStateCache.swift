import Foundation
import NDKSwiftCore

/// A cache for sharing RepostState instances across views
///
/// Instead of each RepostButton creating its own RepostState, they share
/// instances through this cache. When a view disappears and releases its
/// reference, the weak reference in the cache allows the state to be deallocated.
@MainActor
public final class RepostStateCache {
    public static let shared = RepostStateCache()

    private var cache: [String: WeakRef<RepostState>] = [:]
    private let maxCacheSize = 100

    private init() {}

    /// Get or create a RepostState for an event
    /// - Parameters:
    ///   - event: The event to track reposts for
    ///   - ndk: The NDK instance
    /// - Returns: A shared or new RepostState instance
    public func state(for event: NDKEvent, ndk: NDK) -> RepostState {
        let key = event.id

        // Return existing if available and still alive
        if let existing = cache[key]?.value {
            return existing
        }

        // Create new state
        let state = RepostState(ndk: ndk, event: event)
        cache[key] = WeakRef(state)

        // Prune cache if too large
        if cache.count > maxCacheSize {
            pruneCache()
        }

        return state
    }

    /// Remove a specific state from cache (call when view disappears)
    public func remove(for eventId: String) {
        if let ref = cache[eventId], ref.value == nil {
            cache.removeValue(forKey: eventId)
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
