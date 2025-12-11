import SwiftUI

public enum WalletType: String, CaseIterable, Hashable {
    case spark = "spark"
    case cashu = "cashu"

    var displayName: String {
        switch self {
        case .spark: return "Spark (Lightning)"
        case .cashu: return "Cashu (Ecash)"
        }
    }
}

@MainActor
public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()

    @AppStorage("showVideos") public var showVideos: Bool = true
    @AppStorage("autoplayVideos") public var autoplayVideos: Bool = true

    @Published public var walletType: WalletType {
        didSet {
            UserDefaults.standard.set(walletType.rawValue, forKey: "walletType")
        }
    }

    private init() {
        let savedType = UserDefaults.standard.string(forKey: "walletType")
        self.walletType = WalletType(rawValue: savedType ?? "") ?? .spark
    }
}
