import Foundation
import SwiftUI
import BreezSdkSpark
import Security
import Network
import MnemonicSwift
import Observation

// MARK: - SDK Error Extension

extension SdkError {
    var userFriendlyMessage: String {
        switch self {
        case .SparkError(let message):
            return parseSparkError(message)

        case .InvalidUuid(let message):
            return "Invalid identifier: \(message)"

        case .InvalidInput(let message):
            return parseInvalidInputError(message)

        case .NetworkError(let message):
            return parseNetworkError(message)

        case .StorageError:
            return "Storage error: Unable to save wallet data. Please check available storage space."

        case .ChainServiceError(let message):
            return "Blockchain service error: \(message)"

        case .MaxDepositClaimFeeExceeded(_, _, _, let requiredFeeSats, _):
            return "The deposit claim fee (\(requiredFeeSats) sats) is too high. Please try again later when network fees are lower."

        case .MissingUtxo:
            return "Unable to find transaction output. Transaction may not be confirmed yet."

        case .LnurlError(let message):
            return parseLnurlError(message)

        case .Generic(let message):
            return parseGenericError(message)
        }
    }

    private func parseSparkError(_ message: String) -> String {
        let lowercased = message.lowercased()

        if lowercased.contains("mnemonic") || lowercased.contains("seed") {
            return "Invalid recovery phrase. Please check your words and try again."
        }

        if lowercased.contains("insufficient") && lowercased.contains("balance") {
            return "Insufficient balance to complete this transaction."
        }

        if lowercased.contains("timeout") {
            return "Connection timed out. Please check your internet connection and try again."
        }

        return "Wallet error: \(message)"
    }

    private func parseInvalidInputError(_ message: String) -> String {
        let lowercased = message.lowercased()

        if lowercased.contains("invoice") {
            return "Invalid Lightning invoice. Please check the invoice and try again."
        }

        if lowercased.contains("address") {
            return "Invalid Lightning address. Please check the address format."
        }

        if lowercased.contains("amount") {
            return "Invalid amount. Please enter a valid amount in satoshis."
        }

        if lowercased.contains("mnemonic") {
            return "Invalid recovery phrase. Please check that all words are correct and in the right order."
        }

        return "Invalid input: \(message)"
    }

    private func parseNetworkError(_ message: String) -> String {
        let lowercased = message.lowercased()

        if lowercased.contains("no internet") || lowercased.contains("not connected") {
            return "No internet connection. Please check your network settings and try again."
        }

        if lowercased.contains("timeout") {
            return "Connection timed out. Please check your internet connection and try again."
        }

        if lowercased.contains("dns") {
            return "Unable to reach the Lightning service. Please check your internet connection."
        }

        if lowercased.contains("refused") {
            return "Connection refused. The Lightning service may be temporarily unavailable."
        }

        return "Network error: Unable to connect to Lightning service. Please try again."
    }

    private func parseLnurlError(_ message: String) -> String {
        let lowercased = message.lowercased()

        if lowercased.contains("invalid") {
            return "Invalid Lightning URL. Please check the URL and try again."
        }

        if lowercased.contains("expired") {
            return "This Lightning URL has expired. Please request a new one."
        }

        if lowercased.contains("amount") {
            return "The amount is outside the allowed range for this Lightning URL."
        }

        return "Lightning URL error: \(message)"
    }

    private func parseGenericError(_ message: String) -> String {
        let lowercased = message.lowercased()

        if lowercased.contains("payment") && lowercased.contains("failed") {
            return "Payment failed. Please check your balance and try again."
        }

        if lowercased.contains("insufficient") && lowercased.contains("funds") {
            return "Insufficient funds. Please add more sats to your wallet."
        }

        if lowercased.contains("route") || lowercased.contains("routing") {
            return "Unable to find payment route. The recipient may be offline or unreachable."
        }

        if lowercased.contains("expired") {
            return "This invoice has expired. Please request a new one."
        }

        if lowercased.contains("already paid") {
            return "This invoice has already been paid."
        }

        return message.isEmpty ? "An unexpected error occurred. Please try again." : message
    }
}

// MARK: - Wallet Manager

@Observable
@MainActor
public final class SparkWalletManager {
    public private(set) var connectionStatus: SparkConnectionStatus = .disconnected
    public private(set) var balance: UInt64 = 0
    public private(set) var lightningAddress: String?
    public private(set) var isLoading = false
    public private(set) var payments: [Payment] = []
    public var error: String?
    public private(set) var networkStatus: NetworkStatus = .unknown

    // Fiat conversion
    public private(set) var fiatRates: [Rate] = []
    public var preferredCurrency: String = UserDefaults.standard.string(forKey: "preferred_fiat_currency") ?? "USD" {
        didSet {
            UserDefaults.standard.set(preferredCurrency, forKey: "preferred_fiat_currency")
        }
    }

    private var sdk: BreezSdk?
    @ObservationIgnored private var eventListenerId: String?
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.olas.spark.network")

    // Deposit monitoring
    private var activeMonitors: [String: (UInt64, AsyncThrowingStream<DepositState, Error>.Continuation)] = [:]

    private let keychainService = "com.olas.spark"
    private let mnemonicAccount = "spark_mnemonic"

    public init() {
        setupNetworkMonitoring()
    }

    deinit {
        pathMonitor.cancel()
        Task { [weak self] in
            await self?.removeEventListener()
        }
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if path.status == .satisfied {
                    self.networkStatus = .connected
                } else {
                    self.networkStatus = .offline
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - Public Methods

    /// Attempt to restore wallet from keychain on app launch
    public func restoreWalletIfExists() async {
        guard let mnemonic = loadMnemonicFromKeychain() else { return }

        do {
            try await connect(mnemonic: mnemonic)
        } catch {
            // Mnemonic was invalid or connection failed - clear it
            deleteMnemonicFromKeychain()
            self.error = handleError(error)
        }
    }

    /// Create a new wallet with fresh mnemonic
    /// - Returns: The mnemonic (caller must display for user to back up)
    public func createWallet() async throws -> String {
        guard sdk == nil else {
            throw SparkWalletError.alreadyConnected
        }

        isLoading = true
        connectionStatus = .connecting
        defer { isLoading = false }

        // Generate a new mnemonic
        let mnemonic = generateMnemonic()

        // Connect with the new mnemonic
        try await connect(mnemonic: mnemonic)

        // Save mnemonic to keychain
        try saveMnemonicToKeychain(mnemonic)

        return mnemonic
    }

    /// Import existing wallet with mnemonic
    public func importWallet(mnemonic: String) async throws {
        guard sdk == nil else {
            throw SparkWalletError.alreadyConnected
        }

        isLoading = true
        connectionStatus = .connecting
        defer { isLoading = false }

        try await connect(mnemonic: mnemonic)

        // Save mnemonic to keychain
        try saveMnemonicToKeychain(mnemonic)
    }

    /// Connect with existing mnemonic
    private func connect(mnemonic: String) async throws {
        guard sdk == nil else {
            throw SparkWalletError.alreadyConnected
        }

        connectionStatus = .connecting

        let seed = Seed.mnemonic(mnemonic: mnemonic, passphrase: nil)
        var config = defaultConfig(network: .mainnet)
        config.apiKey = OlasConstants.breezApiKey

        let storageDir = getStorageDirectory()

        let connectedSdk = try await BreezSdkSpark.connect(
            request: ConnectRequest(
                config: config,
                seed: seed,
                storageDir: storageDir
            )
        )

        sdk = connectedSdk
        await setupSdk(connectedSdk)
    }

    /// Disconnect and optionally clear stored mnemonic
    public func disconnect(clearMnemonic: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        await removeEventListener()

        // Clean up any active monitors
        for (_, (_, continuation)) in activeMonitors {
            continuation.finish()
        }
        activeMonitors.removeAll()

        if let sdk = sdk {
            try? await sdk.disconnect()
        }

        sdk = nil
        connectionStatus = .disconnected
        balance = 0
        lightningAddress = nil
        payments = []

        if clearMnemonic {
            deleteMnemonicFromKeychain()
        }
    }

    /// Sync wallet with network
    public func sync() async {
        guard let sdk = sdk else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await sdk.syncWallet(request: SyncWalletRequest())
            await refreshInfo()
        } catch {
            self.error = handleError(error)
        }
    }

    /// Refresh balance, info, and payments
    public func refreshInfo() async {
        guard let sdk = sdk else { return }

        do {
            let info = try await sdk.getInfo(request: GetInfoRequest(ensureSynced: false))
            balance = info.balanceSats

            if let addressInfo = try? await sdk.getLightningAddress() {
                lightningAddress = addressInfo.lightningAddress
            }

            // Fetch recent payments
            let response = try await sdk.listPayments(request: ListPaymentsRequest())
            payments = response.payments

            // Fetch fiat rates
            await fetchFiatRates()
        } catch {
            self.error = handleError(error)
        }
    }

    /// Fetch latest fiat exchange rates
    public func fetchFiatRates() async {
        guard let sdk = sdk else { return }

        do {
            let response = try await sdk.listFiatRates()
            fiatRates = response.rates
        } catch {
            // Don't show error to user for fiat rates failure - just log it
            print("[Spark] Failed to fetch fiat rates: \(error)")
        }
    }

    /// Convert sats to fiat using current rates
    public func satsToFiat(_ sats: UInt64) -> Double? {
        guard let rate = fiatRates.first(where: { $0.coin == preferredCurrency }) else {
            return nil
        }
        return SatsConverter.satsToFiat(Int64(sats), btcRate: rate.value)
    }

    /// Convert sats amount to formatted fiat string
    public func formatFiat(_ sats: UInt64) -> String? {
        guard let fiatValue = satsToFiat(sats) else {
            return nil
        }
        return SatsConverter.formatFiat(fiatValue, currencyCode: preferredCurrency)
    }

    /// Parse a payment input (invoice, address, etc.)
    public func parseInput(_ input: String) async throws -> InputType {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }
        return try await sdk.parse(input: input)
    }

    /// Prepare a payment to see fees before sending
    public func preparePayment(input: String, amount: UInt64?) async throws -> PrepareSendPaymentResponse {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        let amountU128: U128? = amount.map { U128(UInt64($0)) }
        return try await sdk.prepareSendPayment(
            request: PrepareSendPaymentRequest(
                paymentRequest: input,
                amount: amountU128
            )
        )
    }

    /// Send a prepared payment
    public func sendPreparedPayment(_ prepared: PrepareSendPaymentResponse) async throws {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        isLoading = true
        defer { isLoading = false }

        _ = try await sdk.sendPayment(
            request: SendPaymentRequest(
                prepareResponse: prepared,
                options: nil,
                idempotencyKey: nil
            )
        )
        await refreshInfo()
    }

    /// Register a lightning address
    public func registerLightningAddress(_ username: String) async throws {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        let info = try await sdk.registerLightningAddress(
            request: RegisterLightningAddressRequest(username: username)
        )
        lightningAddress = info.lightningAddress
    }

    /// Create a Lightning invoice to receive payment with a specific amount
    public func createInvoice(amountSats: UInt64, description: String?) async throws -> String {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        print("[Spark] Creating invoice with amount: \(amountSats) sats, description: \(description ?? "nil")")

        let response = try await sdk.receivePayment(
            request: ReceivePaymentRequest(
                paymentMethod: .bolt11Invoice(
                    description: description ?? "",
                    amountSats: amountSats
                )
            )
        )

        print("[Spark] Generated invoice: \(response.paymentRequest)")
        print("[Spark] Invoice length: \(response.paymentRequest.count) characters")

        return response.paymentRequest
    }

    /// Create a Lightning invoice to receive payment (amount optional for open invoices)
    public func createOpenInvoice(description: String?) async throws -> String {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        print("[Spark] Creating open invoice, description: \(description ?? "nil")")

        let response = try await sdk.receivePayment(
            request: ReceivePaymentRequest(
                paymentMethod: .bolt11Invoice(
                    description: description ?? "",
                    amountSats: nil
                )
            )
        )

        print("[Spark] Generated open invoice: \(response.paymentRequest)")
        print("[Spark] Invoice length: \(response.paymentRequest.count) characters")

        return response.paymentRequest
    }

    /// Monitor an invoice for incoming payment
    /// Returns an async stream that yields deposit state updates
    public func monitorInvoice(
        expectedAmount: UInt64,
        timeout: TimeInterval = 600
    ) -> AsyncThrowingStream<DepositState, Error> {
        return AsyncThrowingStream { continuation in
            let monitorId = UUID().uuidString
            activeMonitors[monitorId] = (expectedAmount, continuation)

            // Don't yield a monitoring state here - we're already in monitoring state
            // Yielding with empty invoice would overwrite the correct invoice

            // Set up timeout task
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if activeMonitors[monitorId] != nil {
                    continuation.yield(.expired)
                    continuation.finish()
                    activeMonitors.removeValue(forKey: monitorId)
                }
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    timeoutTask.cancel()
                    self?.activeMonitors.removeValue(forKey: monitorId)
                }
            }
        }
    }

    /// Pay a Lightning invoice directly
    public func pay(invoice: String) async throws {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        isLoading = true
        defer { isLoading = false }

        let prepared = try await sdk.prepareSendPayment(
            request: PrepareSendPaymentRequest(paymentRequest: invoice)
        )
        _ = try await sdk.sendPayment(
            request: SendPaymentRequest(
                prepareResponse: prepared,
                options: nil,
                idempotencyKey: nil
            )
        )
        await refreshInfo()
    }

    /// Check if wallet has stored mnemonic (can restore)
    public var hasSavedWallet: Bool {
        loadMnemonicFromKeychain() != nil
    }

    /// Retrieve the stored mnemonic from keychain
    /// Warning: This returns the sensitive recovery phrase. Handle with care.
    public func retrieveMnemonic() -> String? {
        loadMnemonicFromKeychain()
    }

    // MARK: - Private Helpers

    private func handleError(_ error: Error) -> String {
        if let sdkError = error as? SdkError {
            return sdkError.userFriendlyMessage
        }
        if let walletError = error as? SparkWalletError {
            return walletError.errorDescription ?? "An unexpected error occurred."
        }
        return error.localizedDescription
    }

    private func setupSdk(_ sdk: BreezSdk) async {
        connectionStatus = .connected

        // Add event listener
        let listener = SparkEventListener { [weak self] event in
            Task { @MainActor in
                await self?.handleEvent(event)
            }
        }
        eventListenerId = await sdk.addEventListener(listener: listener)

        // Fetch initial info
        await refreshInfo()
    }

    private func removeEventListener() async {
        guard let sdk = sdk, let listenerId = eventListenerId else { return }
        _ = await sdk.removeEventListener(id: listenerId)
        eventListenerId = nil
    }

    private func handleEvent(_ event: SdkEvent) async {
        switch event {
        case .synced:
            await refreshInfo()
        case .paymentSucceeded(let payment):
            await refreshInfo()

            // Notify any active monitors if this is a receive payment
            if payment.paymentType == .receive {
                guard let paymentAmount = UInt64(payment.amount.description) else { break }
                for (monitorId, (expectedAmount, continuation)) in activeMonitors {
                    if paymentAmount == expectedAmount {
                        continuation.yield(.completed(amount: Int64(paymentAmount)))
                        continuation.finish()
                        activeMonitors.removeValue(forKey: monitorId)
                    }
                }
            }

            print("[Spark] Payment succeeded: \(payment.amount) sats")
        case .paymentFailed(let payment):
            error = "Payment failed. Please check your balance and try again."
            print("[Spark] Payment failed: \(payment.id)")
        case .paymentPending(let payment):
            print("[Spark] Payment pending: \(payment.amount) sats")
        case .unclaimedDeposits(let deposits):
            print("[Spark] Unclaimed deposits: \(deposits.count)")
        case .claimedDeposits(let deposits):
            print("[Spark] Claimed deposits: \(deposits.count)")
            await refreshInfo()
        }
    }

    private func getStorageDirectory() -> String {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sparkDir = appSupport.appendingPathComponent("spark_wallet", isDirectory: true)

        if !fileManager.fileExists(atPath: sparkDir.path) {
            try? fileManager.createDirectory(at: sparkDir, withIntermediateDirectories: true)
        }

        return sparkDir.path
    }

    private func generateMnemonic() -> String {
        do {
            return try Mnemonic.generateMnemonic(strength: 128)
        } catch {
            fatalError("Failed to generate mnemonic: \(error)")
        }
    }

    // MARK: - Keychain

    private func saveMnemonicToKeychain(_ mnemonic: String) throws {
        guard let data = mnemonic.data(using: .utf8) else {
            throw SparkWalletError.invalidMnemonic
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SparkWalletError.connectionFailed("Failed to save to keychain: \(status)")
        }
    }

    private func loadMnemonicFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let mnemonic = String(data: data, encoding: .utf8) else {
            return nil
        }

        return mnemonic
    }

    private func deleteMnemonicFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Event Listener

private class SparkEventListener: EventListener {
    private let handler: (SdkEvent) -> Void

    init(handler: @escaping (SdkEvent) -> Void) {
        self.handler = handler
    }

    func onEvent(event: SdkEvent) async {
        handler(event)
    }
}

// MARK: - Connection Status

public enum SparkConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    public var icon: String {
        switch self {
        case .disconnected: return "bolt.slash.fill"
        case .connecting: return "bolt.horizontal.fill"
        case .connected: return "bolt.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .disconnected: return .secondary
        case .connecting: return .orange
        case .connected: return OlasTheme.Colors.zapGold
        case .error: return .red
        }
    }

    public var description: String {
        switch self {
        case .disconnected: return "Not Connected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Errors

public enum SparkWalletError: LocalizedError {
    case alreadyConnected
    case notConnected
    case invalidMnemonic
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyConnected:
            return "Wallet is already connected"
        case .notConnected:
            return "Wallet is not connected"
        case .invalidMnemonic:
            return "Invalid mnemonic phrase"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        }
    }
}

// MARK: - Network Status

public enum NetworkStatus: Equatable {
    case unknown
    case connected
    case offline

    public var isOffline: Bool {
        self == .offline
    }
}
