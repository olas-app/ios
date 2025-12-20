import Foundation
import NDKSwiftCore
import Security
import SwiftUI

@MainActor
public final class AuthViewModel: ObservableObject {
    @Published public private(set) var isLoggedIn = false
    @Published public private(set) var currentUser: NDKUser?
    @Published public private(set) var isLoading = false
    @Published public var error: Error?

    public private(set) var signer: (any NDKSigner)?
    public weak var ndk: NDK?

    private let keychainService = "com.olas.keychain"
    private let keychainAccount = "user_nsec"
    private let keychainBunkerAccount = "user_bunker"

    public init() {
        // Session restoration happens in restoreSession()
    }

    public func setNDK(_ ndk: NDK) {
        self.ndk = ndk
    }

    // MARK: - Public Methods

    public func createAccount() async throws {
        isLoading = true
        defer { isLoading = false }

        guard let ndk = ndk else {
            throw AuthError.ndkNotInitialized
        }

        let newSigner = try NDKPrivateKeySigner.generate()
        let nsec = try newSigner.nsec

        try saveToKeychain(nsec: nsec, account: keychainAccount)

        signer = newSigner
        currentUser = try await NDKUser(pubkey: newSigner.pubkey, ndk: ndk)
        isLoggedIn = true
    }

    public func loginWithNsec(_ nsec: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard let ndk = ndk else {
            throw AuthError.ndkNotInitialized
        }

        guard nsec.hasPrefix("nsec1") else {
            throw AuthError.invalidNsec
        }

        let newSigner = try NDKPrivateKeySigner(nsec: nsec)
        try saveToKeychain(nsec: nsec, account: keychainAccount)

        signer = newSigner
        currentUser = try await NDKUser(pubkey: newSigner.pubkey, ndk: ndk)
        isLoggedIn = true
    }

    public func loginWithBunker(_ bunkerUri: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard let ndk = ndk else {
            throw AuthError.ndkNotInitialized
        }

        // Validate bunker URI format
        guard bunkerUri.hasPrefix("bunker://") || bunkerUri.hasPrefix("nostrconnect://") else {
            throw AuthError.invalidBunkerUri
        }

        // Create bunker signer
        let bunkerSigner = try await NDKBunkerSigner.bunker(ndk: ndk, connectionToken: bunkerUri)

        // Connect to the remote signer
        let pubkey = try await bunkerSigner.connect()

        // Save bunker URI to keychain
        try saveToKeychain(nsec: bunkerUri, account: keychainBunkerAccount)

        signer = bunkerSigner
        currentUser = try await NDKUser(pubkey: pubkey, ndk: ndk)
        isLoggedIn = true
    }

    public func loginWithNIP46(bunkerSigner: NDKBunkerSigner, pubkey: PublicKey) async throws {
        isLoading = true
        defer { isLoading = false }

        guard let ndk = ndk else {
            throw AuthError.ndkNotInitialized
        }

        // Save the bunker URI if available
        if let bunkerUri = await bunkerSigner.nostrConnectUri {
            try saveToKeychain(nsec: bunkerUri, account: keychainBunkerAccount)
        }

        signer = bunkerSigner
        currentUser = try await NDKUser(pubkey: pubkey, ndk: ndk)
        isLoggedIn = true
    }

    public func logout() async {
        deleteFromKeychain(account: keychainAccount)
        deleteFromKeychain(account: keychainBunkerAccount)
        signer = nil
        currentUser = nil
        isLoggedIn = false
    }

    public func restoreSession() async {
        // Try to restore bunker session first
        if let bunkerUri = loadFromKeychain(account: keychainBunkerAccount) {
            do {
                try await loginWithBunker(bunkerUri)
                return
            } catch {
                deleteFromKeychain(account: keychainBunkerAccount)
            }
        }

        // Fall back to nsec
        guard let nsec = loadFromKeychain(account: keychainAccount) else { return }

        do {
            try await loginWithNsec(nsec)
        } catch {
            deleteFromKeychain(account: keychainAccount)
        }
    }

    // MARK: - Keychain

    private func saveToKeychain(nsec: String, account: String) throws {
        guard let data = nsec.data(using: .utf8) else {
            throw AuthError.keychainError(-1)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthError.keychainError(status)
        }
    }

    private func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let nsec = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return nsec
    }

    private func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

public enum AuthError: LocalizedError, Equatable {
    case invalidNsec
    case invalidBunkerUri
    case ndkNotInitialized
    case keychainError(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidNsec:
            return "Invalid private key format. Must start with 'nsec1'"
        case .invalidBunkerUri:
            return "Invalid bunker URI. Must start with 'bunker://' or 'nostrconnect://'"
        case .ndkNotInitialized:
            return "NDK not initialized. Please try again."
        case let .keychainError(status):
            return "Keychain error: \(status)"
        }
    }
}
