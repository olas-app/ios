import Foundation

public enum Currency: String, CaseIterable {
    case sat = "SAT"
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"

    public var symbol: String {
        switch self {
        case .sat: return ""
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .jpy: return "¥"
        }
    }

    public var quickAmounts: [Int] {
        switch self {
        case .sat: return [1000, 5000, 10000, 21000, 50000, 100_000]
        case .usd: return [1, 5, 10, 20, 50, 100]
        case .eur: return [1, 5, 10, 20, 50, 100]
        case .gbp: return [1, 5, 10, 20, 50, 100]
        case .jpy: return [100, 500, 1000, 2000, 5000, 10000]
        }
    }
}
