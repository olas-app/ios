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

    public init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.isNewAccount = UserDefaults.standard.bool(forKey: "isNewAccount")
        if let stored = UserDefaults.standard.string(forKey: "walletType"),
           let type = WalletType(rawValue: stored) {
            self.walletType = type
        }
    }
}
