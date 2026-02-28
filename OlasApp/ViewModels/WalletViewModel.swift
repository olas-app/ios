// WalletViewModel.swift
import CashuSwift
import NDKSwiftCashu
import NDKSwiftCore
import SwiftUI

@Observable @MainActor
public final class WalletViewModel {
    let ndk: NDK

    public private(set) var wallet: NIP60Wallet?
    public private(set) var balance: Int64 = 0
    public private(set) var balancesByMint: [String: Int64] = [:]
    public private(set) var isLoading = false
    public private(set) var isSetup = false
    public private(set) var transactions: [WalletTransaction] = []
    public private(set) var configuredMints: [String] = []
    public private(set) var error: Error?
    public private(set) var btcRate: Double?
    public var preferredCurrency: String = UserDefaults.standard.string(forKey: "preferred_fiat_currency") ?? "USD" {
        didSet {
            UserDefaults.standard.set(preferredCurrency, forKey: "preferred_fiat_currency")
        }
    }

    nonisolated(unsafe) private var eventObservationTask: Task<Void, Never>?
    nonisolated(unsafe) private var priceRefreshTask: Task<Void, Never>?

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    deinit {
        eventObservationTask?.cancel()
        priceRefreshTask?.cancel()
    }

    // MARK: - Wallet Lifecycle

    /// Load existing wallet or determine if setup is needed
    public func loadWallet() async {
        guard wallet == nil else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let newWallet = try NIP60Wallet(ndk: ndk)
            wallet = newWallet

            // Start listening for events before loading
            startEventObservation()

            // Load wallet state from relays
            try await newWallet.load()

            // Check if wallet has mints configured (indicates setup complete)
            let mints = await newWallet.mints.getMintURLs()
            isSetup = !mints.isEmpty
            configuredMints = mints

            // Get initial balance
            if let bal = try await newWallet.getBalance() {
                balance = bal
            }
            balancesByMint = await newWallet.getBalancesByMint()

            // Load transaction history
            transactions = await newWallet.getTransactionHistory()

            // Wallet configured - zap manager will use this wallet automatically

            // Fetch initial BTC price
            await fetchBTCPrice()

            // Start periodic price refresh (every 5 minutes)
            startPriceRefreshTask()

        } catch {
            self.error = error
        }
    }

    private func startPriceRefreshTask() {
        priceRefreshTask?.cancel()
        priceRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000) // 5 minutes
                await self?.fetchBTCPrice()
            }
        }
    }

    /// Setup wallet with selected mints and relays
    public func setupWallet(mints: [String], relays: [String]) async throws {
        guard let wallet = wallet else {
            throw WalletError.notInitialized
        }

        isLoading = true
        defer { isLoading = false }

        // Setup publishes kind 17375 (wallet config) and kind 10019 (mint list)
        try await wallet.setup(mints: mints, relays: relays, publishMintList: true)

        isSetup = true
        configuredMints = mints
    }

    // MARK: - Deposit

    /// Request a Lightning invoice for depositing funds
    public func requestDeposit(amount: Int64, mintURL: String) async throws -> CashuMintQuote {
        guard let wallet = wallet else {
            throw WalletError.notInitialized
        }

        return try await wallet.requestMint(amount: amount, mintURL: mintURL, persistQuote: true)
    }

    /// Monitor deposit status
    public func monitorDeposit(quote: CashuMintQuote) async -> AsyncThrowingStream<DepositStatus, Error> {
        guard let wallet = wallet else {
            return AsyncThrowingStream { $0.finish(throwing: WalletError.notInitialized) }
        }

        return await wallet.monitorDeposit(quote: quote)
    }

    // MARK: - Send/Withdraw

    /// Pay a Lightning invoice
    public func payLightningInvoice(_ invoice: String, amount: Int64) async throws -> (preimage: String, feePaid: Int64?) {
        guard let wallet = wallet else {
            throw WalletError.notInitialized
        }

        let result = try await wallet.payLightning(invoice: invoice, amount: amount)

        // Refresh balance after payment
        await refreshBalance()

        return result
    }

    /// Create a Cashu token for offline sending
    public func createToken(amount: Int64, mint: URL) async throws -> String {
        guard let wallet = wallet else {
            throw WalletError.notInitialized
        }

        // Get proofs for the amount
        let proofs = await wallet.proofStateManager.getAvailableProofs(mint: mint.absoluteString)

        // Select proofs that cover the amount
        var selectedProofs: [CashuSwift.Proof] = []
        var total: Int64 = 0

        for proof in proofs {
            if total >= amount { break }
            selectedProofs.append(proof)
            total += Int64(proof.amount)
        }

        guard total >= amount else {
            throw WalletError.insufficientBalance
        }

        return try await wallet.createTokenFromProofs(proofs: selectedProofs, mint: mint)
    }

    // MARK: - Balance & Transactions

    /// Refresh wallet balance
    public func refreshBalance() async {
        guard let wallet = wallet else { return }

        if let bal = try? await wallet.getBalance() {
            balance = bal
        }
        balancesByMint = await wallet.getBalancesByMint()
    }

    /// Refresh transaction history
    public func refreshTransactions() async {
        guard let wallet = wallet else { return }
        transactions = await wallet.getTransactionHistory()
    }

    // MARK: - Fiat Conversion

    /// Fetch BTC price from CoinGecko API
    public func fetchBTCPrice() async {
        do {
            let urlString = "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=\(preferredCurrency.lowercased())"
            guard let url = URL(string: urlString) else { return }

            let (data, _) = try await URLSession.shared.data(from: url)

            struct PriceResponse: Codable {
                let bitcoin: [String: Double]
            }

            let response = try JSONDecoder().decode(PriceResponse.self, from: data)
            if let rate = response.bitcoin[preferredCurrency.lowercased()] {
                btcRate = rate
            }
        } catch {}
    }

    /// Convert sats to fiat using current rate
    public func satsToFiat(_ sats: Int64) -> Double? {
        guard let rate = btcRate else { return nil }
        return SatsConverter.satsToFiat(sats, btcRate: rate)
    }

    /// Format fiat amount with currency symbol
    public func formatFiat(_ sats: Int64) -> String? {
        guard let fiatValue = satsToFiat(sats) else { return nil }
        return SatsConverter.formatFiat(fiatValue, currencyCode: preferredCurrency)
    }

    // MARK: - Event Observation

    private func startEventObservation() {
        guard let wallet = wallet else { return }

        eventObservationTask?.cancel()
        eventObservationTask = Task { [weak self] in
            let events = await wallet.events
            for await event in events {
                guard let self = self else { break }

                await MainActor.run {
                    self.handleWalletEvent(event)
                }
            }
        }
    }

    private func handleWalletEvent(_ event: NIP60WalletEvent) {
        switch event.type {
        case let .balanceChanged(newBalance):
            balance = newBalance
            Task {
                balancesByMint = await wallet?.getBalancesByMint() ?? [:]
            }

        case let .configurationUpdated(mints):
            configuredMints = mints
            isSetup = !mints.isEmpty

        case let .mintsAdded(added):
            for mint in added {
                if !configuredMints.contains(mint) {
                    configuredMints.append(mint)
                }
            }

        case let .mintsRemoved(removed):
            configuredMints.removeAll { removed.contains($0) }

        case .nutzapReceived:
            // Refresh transactions when nutzap activity occurs
            Task {
                await refreshTransactions()
            }

        case .transactionAdded, .transactionUpdated:
            // Refresh transactions
            Task {
                await refreshTransactions()
            }

        @unknown default:
            break
        }
    }

    // MARK: - Zapping

    /// Send a zap (nutzap or Lightning) to an event
    public func zap(event: NDKEvent, amount: Int64, comment: String? = nil) async throws {
        _ = try await event.zap(
            with: ndk,
            amountSats: amount,
            comment: comment,
            preferredType: nil,
            preferredProvider: nil
        )

        // Refresh balance after zap
        await refreshBalance()
    }
}

// MARK: - Errors

public enum WalletError: LocalizedError {
    case notInitialized
    case insufficientBalance
    case invalidMint
    case setupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Wallet not initialized"
        case .insufficientBalance:
            return "Insufficient balance"
        case .invalidMint:
            return "Invalid mint"
        case let .setupFailed(reason):
            return "Wallet setup failed: \(reason)"
        }
    }
}
