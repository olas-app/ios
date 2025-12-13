import BreezSdkSpark
import Foundation

extension U128 {
    var formattedString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let amountString = description
        if let number = Decimal(string: amountString) {
            return formatter.string(from: number as NSDecimalNumber) ?? amountString
        }
        return amountString
    }

    var formattedSats: String {
        return "\(formattedString) sats"
    }
}
