import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// ViewModel for ProfileView that handles all data loading and business logic
@MainActor
@Observable
class ProfileViewModel {
    // MARK: - Published State

    var profile: NDKUserMetadata?
    var posts: [NDKEvent] = []
    var likedPosts: [NDKEvent] = []
    var followingCount: Int = 0
    var selectedTab: ProfileTab = .posts

    // MARK: - Private State

    private let ndk: NDK
    private let pubkey: String
    private let settings: SettingsManager
    private var likedMetaSubscription: NDKMetaSubscription?

    // MARK: - Computed Properties

    var currentPosts: [NDKEvent] {
        selectedTab == .posts ? posts : likedPosts
    }

    private var feedKinds: [Kind] {
        var kinds: [Kind] = [OlasConstants.EventKinds.image]
        if settings.showVideos {
            kinds.append(OlasConstants.EventKinds.shortVideo)
        }
        return kinds
    }

    // MARK: - Initialization

    init(ndk: NDK, pubkey: String, settings: SettingsManager) {
        self.ndk = ndk
        self.pubkey = pubkey
        self.settings = settings
    }

    // MARK: - Data Loading

    /// Starts all data loading tasks
    func startLoading() {
        Task { await loadProfile() }
        Task { await loadPosts() }
        Task { await loadLikedPosts() }
        Task { await loadFollowing() }
    }

    /// Loads user profile metadata
    private func loadProfile() async {
        for await metadata in await ndk.profileManager.subscribe(for: pubkey, maxAge: 60) {
            self.profile = metadata
        }
    }

    /// Loads user's posts with efficient batch insertion
    private func loadPosts() async {
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: feedKinds,
            limit: 50
        )

        let subscription = ndk.subscribe(filter: filter)
        var buffer: [NDKEvent] = []

        for await event in subscription.events {
            buffer.append(event)

            // Batch insert every 10 events for efficiency
            if buffer.count >= 10 {
                insertPostsBatch(buffer)
                buffer.removeAll()
            }
        }

        // Insert remaining events
        if !buffer.isEmpty {
            insertPostsBatch(buffer)
        }
    }

    /// Efficiently inserts a batch of posts maintaining sort order
    private func insertPostsBatch(_ newPosts: [NDKEvent]) {
        // Combine and sort all at once - O(n log n) vs O(n²) for individual inserts
        let combined = posts + newPosts
        posts = combined.sorted { $0.createdAt > $1.createdAt }
    }

    /// Loads posts the user has liked
    private func loadLikedPosts() async {
        let likeFilter = NDKFilter(
            authors: [pubkey],
            kinds: [Kind(7)],
            limit: 100
        )

        likedMetaSubscription = ndk.metaSubscribe(
            filter: likeFilter,
            sort: .tagTime
        )

        // Update liked posts when subscription changes
        if let subscription = likedMetaSubscription {
            likedPosts = subscription.events
        }
    }

    /// Loads the count of users this profile follows
    private func loadFollowing() async {
        let user = NDKUser(pubkey: pubkey)
        await user.setNdk(ndk)

        do {
            let follows = try await user.follows()
            self.followingCount = follows.count
        } catch {
            self.followingCount = 0
        }
    }

    /// Reloads the profile data
    func refreshProfile() async {
        await loadProfile()
    }
}
