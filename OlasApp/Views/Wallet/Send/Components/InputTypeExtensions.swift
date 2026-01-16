import BreezSdkSpark

// MARK: - InputType Extensions

public extension InputType {
    /// Human-readable description of the input type
    var typeDescription: String {
        switch self {
        case .bolt11Invoice: return "Lightning Invoice"
        case .bolt12Invoice: return "BOLT12 Invoice"
        case .bolt12Offer: return "BOLT12 Offer"
        case .lnurlPay: return "LNURL Pay"
        case .lnurlWithdraw: return "LNURL Withdraw"
        case .lnurlAuth: return "LNURL Auth"
        case .bitcoinAddress: return "Bitcoin Address"
        case .lightningAddress: return "Lightning Address"
        case .sparkAddress: return "Spark Address"
        case .sparkInvoice: return "Spark Invoice"
        case .bip21: return "BIP21 URI"
        case .bolt12InvoiceRequest: return "BOLT12 Request"
        case .silentPaymentAddress: return "Silent Payment"
        case .url: return "URL"
        }
    }

    /// Whether this input type requires a user-specified amount
    var requiresAmount: Bool {
        switch self {
        case .bolt11Invoice:
            // Assuming amount is always embedded in invoice
            return false
        case .lnurlPay, .lightningAddress, .sparkAddress:
            return true
        case .bitcoinAddress:
            // Assuming amount is always embedded
            return false
        default:
            return false
        }
    }

    /// The embedded amount in satoshis, if available
    var embeddedAmountSats: UInt64? {
        switch self {
        case .bolt11Invoice:
            // amountSats property removed from BreezSDK
            return nil
        case .bitcoinAddress:
            // amountSats property removed from BreezSDK
            return nil
        default:
            return nil
        }
    }

    /// Whether this is a supported payment type
    var isSupported: Bool {
        switch self {
        case .bolt11Invoice, .lightningAddress, .lnurlPay, .sparkAddress, .sparkInvoice:
            return true
        default:
            return false
        }
    }
}
