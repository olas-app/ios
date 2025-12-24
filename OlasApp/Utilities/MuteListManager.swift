// MuteListManager.swift
import Combine
import NDKSwiftCore
import SwiftUI

/// Manages mute lists from multiple sources:
/// 1. The current user's personal mute list (for muting/unmuting actions)
/// 2. Centralized mute lists from configurable pubkeys (for content moderation)
///
/// Events from authors appearing in ANY of these mute lists will be filtered out.
@MainActor
public final class MuteListManager: ObservableObject {
    /// Combined set of all muted pubkeys from all sources
    @Published public private(set) var mutedPubkeys: Set<String> = []

    /// The current user's personal mute list (used for mute/unmute actions)
    @Published public private(set) var userMutedPubkeys: Set<String> = []

    /// Pubkeys whose mute lists we subscribe to for centralized moderation
    public private(set) var muteListSources: [String]

    private let ndk: NDK
    private var userSubscriptionTask: Task<Void, Never>?
    private var centralizedSubscriptionTask: Task<Void, Never>?

    /// Muted pubkeys per source (for tracking/debugging)
    private var mutedBySource: [String: Set<String>] = [:]

    public init(ndk: NDK, muteListSources: [String] = OlasConstants.defaultMuteListSources) {
        self.ndk = ndk
        self.muteListSources = muteListSources
    }

    /// Updates the mute list sources and restarts subscriptions
    public func updateMuteListSources(_ sources: [String]) {
        muteListSources = sources
        stopCentralizedSubscription()
        startCentralizedSubscription()
    }

    /// Starts all mute list subscriptions (user + centralized sources)
    public func startSubscription() {
        startUserSubscription()
        startCentralizedSubscription()
    }

    /// Starts subscription to the current user's mute list
    private func startUserSubscription() {
        userSubscriptionTask?.cancel()
        userSubscriptionTask = Task {
            guard let currentUser = await ndk.currentUser else { return }

            let filter = NDKFilter(
                authors: [currentUser.pubkey],
                kinds: [OlasConstants.EventKinds.muteList],
                limit: 1
            )

            let subscription = ndk.subscribe(filter: filter, cachePolicy: .cacheWithNetwork)

            for await events in subscription.events {
                guard !Task.isCancelled else { break }
                for event in events {
                    parseUserMuteList(from: event)
                }
            }
        }
    }

    /// Starts open subscription to centralized mute list sources
    private func startCentralizedSubscription() {
        guard !muteListSources.isEmpty else { return }

        centralizedSubscriptionTask?.cancel()
        centralizedSubscriptionTask = Task {
            let filter = NDKFilter(
                authors: muteListSources,
                kinds: [OlasConstants.EventKinds.muteList]
            )

            // Keep subscription open with network priority to get real-time updates
            let subscription = ndk.subscribe(filter: filter, cachePolicy: .cacheWithNetwork)

            for await events in subscription.events {
                guard !Task.isCancelled else { break }
                for event in events {
                    parseCentralizedMuteList(from: event)
                }
            }
        }
    }

    public func stopSubscription() {
        stopUserSubscription()
        stopCentralizedSubscription()
    }

    private func stopUserSubscription() {
        userSubscriptionTask?.cancel()
        userSubscriptionTask = nil
    }

    private func stopCentralizedSubscription() {
        centralizedSubscriptionTask?.cancel()
        centralizedSubscriptionTask = nil
    }

    /// Parses the current user's mute list
    private func parseUserMuteList(from event: NDKEvent) {
        var pubkeys = Set<String>()
        for tag in event.tags {
            if tag.first == "p", tag.count > 1 {
                pubkeys.insert(tag[1])
            }
        }
        userMutedPubkeys = pubkeys
        recalculateMutedPubkeys()
    }

    /// Parses a centralized mute list from a source pubkey
    private func parseCentralizedMuteList(from event: NDKEvent) {
        var pubkeys = Set<String>()
        for tag in event.tags {
            if tag.first == "p", tag.count > 1 {
                pubkeys.insert(tag[1])
            }
        }
        mutedBySource[event.pubkey] = pubkeys
        recalculateMutedPubkeys()
    }

    /// Recalculates the combined muted pubkeys from all sources
    private func recalculateMutedPubkeys() {
        var combined = userMutedPubkeys
        for (_, pubkeys) in mutedBySource {
            combined.formUnion(pubkeys)
        }
        mutedPubkeys = combined
    }

    public func mute(_ pubkey: String) async throws {
        userMutedPubkeys.insert(pubkey)
        recalculateMutedPubkeys()
        try await publishMuteList()
    }

    public func unmute(_ pubkey: String) async throws {
        userMutedPubkeys.remove(pubkey)
        recalculateMutedPubkeys()
        try await publishMuteList()
    }

    /// Checks if a pubkey is muted by ANY source
    public func isMuted(_ pubkey: String) -> Bool {
        mutedPubkeys.contains(pubkey)
    }

    /// Checks if a pubkey is muted by the current user specifically
    public func isMutedByUser(_ pubkey: String) -> Bool {
        userMutedPubkeys.contains(pubkey)
    }

    private func publishMuteList() async throws {
        let pubkeys = userMutedPubkeys
        _ = try await ndk.publish { builder in
            var b = builder
                .kind(OlasConstants.EventKinds.muteList)
                .content("")

            for pubkey in pubkeys {
                b = b.tag(["p", pubkey])
            }

            return b
        }
    }
}
