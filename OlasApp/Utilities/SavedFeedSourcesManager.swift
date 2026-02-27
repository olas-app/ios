import Foundation
import Observation

/// Manages saved follow packs for feed source selection
@Observable
@MainActor
public final class SavedFeedSourcesManager {
    // MARK: - UserDefaults Keys

    private static let packsKey = "com.olas.savedPacks"
    private static let activeModeKey = "com.olas.activeFeedMode"
    private static let hashtagsKey = "com.olas.savedHashtags"

    // MARK: - Published State

    public private(set) var savedPacks: [SavedPack] = []
    public private(set) var savedHashtags: [String] = []
    public var activeFeedMode: FeedMode = .following {
        didSet { persistActiveFeedMode() }
    }

    // MARK: - Initialization

    public init() {
        load()
    }

    // MARK: - Pack Management

    func savePack(_ pack: FollowPack) {
        let savedPack = SavedPack(from: pack)
        guard !savedPacks.contains(where: { $0.id == savedPack.id }) else { return }
        savedPacks.append(savedPack)
        persistPacks()
    }

    public func removePack(id: String) {
        savedPacks.removeAll { $0.id == id }
        persistPacks()

        // Reset to following if we removed the active pack
        if case .pack(let pack) = activeFeedMode, pack.id == id {
            activeFeedMode = .following
        }
    }

    public func isPacked(_ packId: String) -> Bool {
        savedPacks.contains { $0.id == packId }
    }

    // MARK: - Hashtag Management

    func saveHashtag(_ tag: String) {
        let normalized = tag.lowercased()
        guard !savedHashtags.contains(normalized) else { return }
        savedHashtags.append(normalized)
        persistHashtags()
    }

    func removeHashtag(_ tag: String) {
        let normalized = tag.lowercased()
        savedHashtags.removeAll { $0 == normalized }
        persistHashtags()

        if case .hashtag(let activeTag) = activeFeedMode, activeTag == normalized {
            activeFeedMode = .following
        }
    }

    func isHashtagSaved(_ tag: String) -> Bool {
        savedHashtags.contains(tag.lowercased())
    }

    // MARK: - Persistence

    private func load() {
        loadPacks()
        loadHashtags()
        loadActiveFeedMode()
    }

    private func loadPacks() {
        guard let data = UserDefaults.standard.data(forKey: Self.packsKey),
              let packs = try? JSONDecoder().decode([SavedPack].self, from: data) else {
            return
        }
        savedPacks = packs
    }

    private func loadActiveFeedMode() {
        guard let data = UserDefaults.standard.data(forKey: Self.activeModeKey),
              let mode = try? JSONDecoder().decode(FeedMode.self, from: data) else {
            activeFeedMode = .following
            return
        }

        // Validate the mode still exists
        switch mode {
        case .following, .relay:
            activeFeedMode = mode
        case .pack(let pack):
            if savedPacks.contains(where: { $0.id == pack.id }) {
                activeFeedMode = mode
            } else {
                activeFeedMode = .following
            }
        case .hashtag(let tag):
            if savedHashtags.contains(tag) {
                activeFeedMode = mode
            } else {
                activeFeedMode = .following
            }
        }
    }

    private func loadHashtags() {
        savedHashtags = UserDefaults.standard.stringArray(forKey: Self.hashtagsKey) ?? []
    }

    private func persistHashtags() {
        UserDefaults.standard.set(savedHashtags, forKey: Self.hashtagsKey)
    }

    private func persistPacks() {
        guard let data = try? JSONEncoder().encode(savedPacks) else { return }
        UserDefaults.standard.set(data, forKey: Self.packsKey)
    }

    private func persistActiveFeedMode() {
        guard let data = try? JSONEncoder().encode(activeFeedMode) else { return }
        UserDefaults.standard.set(data, forKey: Self.activeModeKey)
    }
}
