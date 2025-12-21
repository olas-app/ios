// NWCWalletManager.swift
import Foundation
import NDKSwiftCore
import Observation
import Security
import SwiftUI
import UIKit

@Observable
@MainActor
public final class NWCWalletManager {
    // MARK: - Published Properties

    public private(set) var connectionStatus: NWCConnectionStatus = .disconnected
    public private(set) var balance: Int64 = 0
    public private(set) var isLoading = false
    public private(set) var transactions: [NDKSwiftCore.Transaction] = []
    public private(set) var walletInfo: GetInfoResponse?
    public var error: String?

    // Fiat conversion
    public var preferredCurrency: String = UserDefaults.standard.string(forKey: "preferred_fiat_currency") ?? "USD" {
        didSet {
            UserDefaults.standard.set(preferredCurrency, forKey: "preferred_fiat_currency")
        }
    }
    public private(set) var btcRate: Double?

    // MARK: - Private Properties

    private let ndk: NDK
    private var nwcWallet: NDKNWCWallet?
    private var connectionURI: String?
    private let keychainService = "com.olas.nwc"
    private let uriAccount = "nwc_connection_uri"
    private var priceRefreshTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    deinit {
        // Price refresh task will be cancelled automatically when manager is deallocated
    }

    // MARK: - Connection Management

    /// Restore wallet connection from saved URI
    public func restoreConnectionIfExists() async {
        guard let savedURI = loadURIFromKeychain() else { return }

        do {
            try await connect(walletConnectURI: savedURI)
        } catch {
            self.error = handleError(error)
            deleteURIFromKeychain()
        }
    }

    private func debugLog(_ message: String) {
        let logPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("nwc_debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath.path) {
                if let handle = try? FileHandle(forWritingTo: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logPath)
            }
        }
        print(message) // Also print to console
    }

    /// Connect to NWC wallet using a connection URI
    public func connect(walletConnectURI: String) async throws {
        debugLog("[NWCManager] connect() called with URI length: \(walletConnectURI.count)")

        guard nwcWallet == nil else {
            debugLog("[NWCManager] ERROR: Already connected")
            throw NWCWalletError.alreadyConnected
        }

        isLoading = true
        connectionStatus = .connecting
        defer { isLoading = false }

        do {
            debugLog("[NWCManager] Creating NDKNWCWallet...")
            let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: walletConnectURI)
            debugLog("[NWCManager] Wallet created, calling connect()...")

            try await wallet.connect()
            debugLog("[NWCManager] Connect succeeded!")

            nwcWallet = wallet
            connectionURI = walletConnectURI
            connectionStatus = .connected

            try saveURIToKeychain(walletConnectURI)
            await refreshInfo()
            await fetchBTCPrice()
            startPriceRefreshTask()
        } catch {
            debugLog("[NWCManager] ERROR: \(error)")
            throw error
        }
    }

    /// Disconnect from NWC wallet
    public func disconnect(clearURI: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        priceRefreshTask?.cancel()
        priceRefreshTask = nil

        if let wallet = nwcWallet {
            await wallet.disconnect()
        }

        nwcWallet = nil
        connectionURI = nil
        connectionStatus = .disconnected
        balance = 0
        transactions = []
        walletInfo = nil

        if clearURI {
            deleteURIFromKeychain()
        }
    }

    // MARK: - Wallet Operations

    /// Refresh balance, info, and transactions
    public func refreshInfo() async {
        guard let wallet = nwcWallet else { return }

        // Fetch wallet info
        do {
            let info = try await wallet.getInfo()
            walletInfo = info
            debugLog("[NWCManager] Got wallet info: \(info.methods.count) methods supported: \(info.methods.joined(separator: ", "))")
        } catch {
            debugLog("[NWCManager] Failed to get wallet info: \(error)")
        }

        // Fetch balance (independent of info)
        do {
            if let bal = try await wallet.getBalance() {
                balance = bal
                debugLog("[NWCManager] Got balance: \(bal) sats")
            }
        } catch {
            debugLog("[NWCManager] Failed to get balance: \(error)")
        }

        // Fetch transactions (only if wallet supports it)
        if let info = walletInfo, info.methods.contains("list_transactions") {
            do {
                transactions = try await wallet.listTransactions()
                debugLog("[NWCManager] Got \(transactions.count) transactions")
            } catch {
                debugLog("[NWCManager] Failed to get transactions: \(error)")
            }
        } else {
            debugLog("[NWCManager] Wallet does not support list_transactions")
        }

        // Fetch BTC price
        await fetchBTCPrice()
    }

    /// Pay a Lightning invoice
    public func payInvoice(_ invoice: String) async throws -> PayInvoiceResponse {
        guard let wallet = nwcWallet else {
            throw NWCWalletError.notConnected
        }

        isLoading = true
        defer { isLoading = false }

        let response = try await wallet.payInvoice(invoice)
        await refreshInfo()
        return response
    }

    /// Create a Lightning invoice
    public func createInvoice(amountSats: Int64, description: String?) async throws -> String {
        guard let wallet = nwcWallet else {
            throw NWCWalletError.notConnected
        }

        isLoading = true
        defer { isLoading = false }

        let response = try await wallet.makeInvoice(
            amount: amountSats * 1000, // Convert to millisats
            description: description
        )

        return response.invoice ?? ""
    }

    /// Create an invoice for open amount
    public func createOpenInvoice(description: String?) async throws -> String {
        guard let wallet = nwcWallet else {
            throw NWCWalletError.notConnected
        }

        isLoading = true
        defer { isLoading = false }

        let response = try await wallet.makeInvoice(
            amount: nil,
            description: description
        )

        return response.invoice ?? ""
    }

    // MARK: - Fiat Conversion

    private func startPriceRefreshTask() {
        priceRefreshTask?.cancel()
        priceRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000) // 5 minutes
                await self?.fetchBTCPrice()
            }
        }
    }

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
        } catch {
            print("[NWC] Failed to fetch BTC price: \(error)")
        }
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

    // MARK: - Helper Properties

    /// Check if wallet has stored URI (can restore)
    public var hasSavedWallet: Bool {
        loadURIFromKeychain() != nil
    }

    /// Retrieve the stored connection URI from keychain
    public func retrieveConnectionURI() -> String? {
        loadURIFromKeychain()
    }

    // MARK: - Private Helpers

    private func handleError(_ error: Error) -> String {
        if let nwcError = error as? NWCWalletError {
            return nwcError.errorDescription ?? "Unknown error"
        }
        if let ndkError = error as? NDKError {
            return ndkError.localizedDescription
        }
        return error.localizedDescription
    }

    // MARK: - Keychain Management

    private func saveURIToKeychain(_ uri: String) throws {
        guard let data = uri.data(using: .utf8) else {
            throw NWCWalletError.invalidURI
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: uriAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NWCWalletError.connectionFailed("Failed to save to keychain: \(status)")
        }
    }

    private func loadURIFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: uriAccount,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let uri = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return uri
    }

    private func deleteURIFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: uriAccount,
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

public enum NWCWalletError: LocalizedError {
    case alreadyConnected
    case notConnected
    case invalidURI
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyConnected:
            return "Wallet is already connected"
        case .notConnected:
            return "Wallet is not connected"
        case .invalidURI:
            return "Invalid wallet connect URI. Please check the format."
        case let .connectionFailed(reason):
            return "Connection failed: \(reason)"
        }
    }
}

// MARK: - NWC Deep Links (NIP-47 PR #1777)

public struct NWCWallet: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let iconName: String  // SF Symbol name OR asset image name
    public let iconIsAsset: Bool // true = asset image, false = SF Symbol
    public let scheme: String

    public init(id: String, name: String, iconName: String, iconIsAsset: Bool = false, scheme: String) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.iconIsAsset = iconIsAsset
        self.scheme = scheme
    }

    public var connectURL: URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "connect"
        return components.url
    }
}

extension NWCWalletManager {
    /// Known NWC-compatible wallets that support deep link pairing (NIP-47 PR #1777)
    /// Format: nostrnwc+{app_name}://connect for app-specific, nostrnwc://connect for generic
    public static let knownWallets: [NWCWallet] = [
        NWCWallet(id: "primal", name: "Primal", iconName: "PrimalLogo", iconIsAsset: true, scheme: "nostrnwc+primal"),
        NWCWallet(id: "generic", name: "Other Wallet", iconName: "NWCLogo", iconIsAsset: true, scheme: "nostrnwc"),
    ]

    /// Detects which NWC wallets are installed on the device
    public func detectInstalledWallets() async -> [NWCWallet] {
        var installed: [NWCWallet] = []

        for wallet in Self.knownWallets {
            guard let testURL = wallet.connectURL else {
                debugLog("[NWC DeepLink] Failed to create URL for wallet: \(wallet.name)")
                continue
            }

            debugLog("[NWC DeepLink] Testing URL: \(testURL.absoluteString)")
            let canOpen = UIApplication.shared.canOpenURL(testURL)
            debugLog("[NWC DeepLink] canOpenURL(\(wallet.name)) for \(testURL): \(canOpen)")

            if canOpen {
                installed.append(wallet)
            }
        }

        debugLog("[NWC DeepLink] Detected wallets: \(installed.map { $0.name })")
        return installed
    }

    /// Builds the deep link URL to initiate NWC pairing with a wallet
    public func buildDeepLinkURL(wallet: NWCWallet) -> URL? {
        guard let baseURL = wallet.connectURL else { return nil }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "appname", value: "Olas"),
            URLQueryItem(name: "appicon", value: "https://olas.app/icon.png"),
            URLQueryItem(name: "callback", value: "olas://nwc"),
        ]

        return components?.url
    }
}
