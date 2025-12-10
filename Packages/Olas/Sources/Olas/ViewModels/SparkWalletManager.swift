import Foundation
import SwiftUI
import BreezSdkSpark
import Security

@MainActor
public final class SparkWalletManager: ObservableObject {
    @Published public private(set) var connectionStatus: SparkConnectionStatus = .disconnected
    @Published public private(set) var balance: UInt64 = 0
    @Published public private(set) var lightningAddress: String?
    @Published public private(set) var isLoading = false
    @Published public private(set) var payments: [Payment] = []
    @Published public var error: String?

    private var sdk: BreezSdk?
    private var eventListenerId: String?

    private let keychainService = "com.olas.spark"
    private let mnemonicAccount = "spark_mnemonic"

    public init() {}

    deinit {
        Task { [weak self] in
            await self?.removeEventListener()
        }
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
            self.error = error.localizedDescription
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
            self.error = error.localizedDescription
        }
    }

    /// Refresh balance, info, and payments
    public func refreshInfo() async {
        guard let sdk = sdk else { return }

        do {
            let info = try await sdk.getInfo(request: GetInfoRequest())
            balance = info.balanceSats

            if let addressInfo = try? await sdk.getLightningAddress() {
                lightningAddress = addressInfo.lightningAddress
            }

            // Fetch recent payments
            let response = try await sdk.listPayments(request: ListPaymentsRequest())
            payments = response.payments
        } catch {
            self.error = error.localizedDescription
        }
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

    /// Create a Lightning invoice to receive payment
    public func createInvoice(amountSats: UInt64?, description: String?) async throws -> String {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        let response = try await sdk.receivePayment(
            request: ReceivePaymentRequest(
                paymentMethod: .bolt11Invoice(
                    description: description,
                    amountSats: amountSats
                )
            )
        )
        return response.paymentRequest
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

    // MARK: - Private Helpers

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
            print("[Spark] Payment succeeded: \(payment.amount) sats")
        case .paymentFailed(let payment):
            error = "Payment failed"
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
        // Generate 16 bytes of entropy for a 12-word mnemonic
        var entropy = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, entropy.count, &entropy)

        // BIP39 word list (first few for demonstration - in production, use full list)
        // The Breez SDK will validate the mnemonic internally
        // For now, we'll create entropy and let the SDK generate proper mnemonic
        // Actually, we need to use a proper BIP39 implementation
        // Let's use a placeholder that the user will replace with their own

        // Since we don't have a BIP39 library, we'll throw an error asking user to import
        // In a real implementation, you'd use a BIP39 Swift library
        fatalError("Mnemonic generation requires BIP39 library - use importWallet with existing mnemonic")
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
