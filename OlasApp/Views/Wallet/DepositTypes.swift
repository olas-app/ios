import Foundation

public enum DepositWallet {
    case spark(SparkWalletManager)
    case cashu(WalletViewModel, selectedMint: String)
    case nwc(NWCWalletManager)
}

public enum DepositState: Equatable {
    case idle
    case generating
    case monitoring(invoice: String, amount: Int64)
    case completed(amount: Int64)
    case expired
    case error(String)
}
