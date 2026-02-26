import Observation
import SwiftUI

public enum WalletType: String, CaseIterable, Hashable {
    case spark
    case cashu
    case nwc

    var displayName: String {
        switch self {
        case .spark: return "Spark (Lightning)"
        case .cashu: return "Cashu (Ecash)"
        case .nwc: return "NWC (Remote Wallet)"
        }
    }
}

@Observable
@MainActor
public final class SettingsManager {
    @ObservationIgnored @AppStorage("showVideos") public var showVideos: Bool = true
    @ObservationIgnored @AppStorage("autoplayVideos") public var autoplayVideos: Bool = true
    @ObservationIgnored @AppStorage("showRelayIndicator") public var showRelayIndicator: Bool = false

    public var hasCompletedOnboarding: Bool = false {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }

    public var isNewAccount: Bool = false {
        didSet {
            UserDefaults.standard.set(isNewAccount, forKey: "isNewAccount")
        }
    }

    public var walletType: WalletType = .spark {
        didSet {
            UserDefaults.standard.set(walletType.rawValue, forKey: "walletType")
        }
    }

    /// Pubkeys whose mute lists are used for content filtering.
    /// Defaults to OlasConstants.defaultMuteListSources if not customized.
    public var muteListSources: [String] = [] {
        didSet {
            UserDefaults.standard.set(muteListSources, forKey: "muteListSources")
        }
    }

    public init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.isNewAccount = UserDefaults.standard.bool(forKey: "isNewAccount")
        if let stored = UserDefaults.standard.string(forKey: "walletType"),
           let type = WalletType(rawValue: stored) {
            self.walletType = type
        }
        // Load mute list sources, defaulting to constants if not set
        if let stored = UserDefaults.standard.array(forKey: "muteListSources") as? [String] {
            self.muteListSources = stored
        } else {
            self.muteListSources = OlasConstants.defaultMuteListSources
        }
    }

    /// Adds a pubkey to the mute list sources
    public func addMuteListSource(_ pubkey: String) {
        guard !muteListSources.contains(pubkey) else { return }
        muteListSources.append(pubkey)
    }

    /// Removes a pubkey from the mute list sources
    public func removeMuteListSource(_ pubkey: String) {
        muteListSources.removeAll { $0 == pubkey }
    }

    /// Resets mute list sources to defaults
    public func resetMuteListSourcesToDefaults() {
        muteListSources = OlasConstants.defaultMuteListSources
    }
}
