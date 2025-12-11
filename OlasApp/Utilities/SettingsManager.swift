import SwiftUI
import Observation

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

@Observable
@MainActor
public final class SettingsManager {
    // Shared instance removed
    // public static let shared = SettingsManager()

    @ObservationIgnored @AppStorage("showVideos") public var showVideos: Bool = true
    @ObservationIgnored @AppStorage("autoplayVideos") public var autoplayVideos: Bool = true
    @ObservationIgnored @AppStorage("walletType") public var walletType: WalletType = .spark

    public init() {}
}
