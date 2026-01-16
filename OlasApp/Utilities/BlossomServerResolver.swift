import Foundation
import NDKSwiftCore

/// Errors that can occur when resolving a Blossom server URL
public enum BlossomServerError: LocalizedError {
    case noServerConfigured
    case invalidServerURL(String)

    public var errorDescription: String? {
        switch self {
        case .noServerConfigured:
            return "No upload server configured. Please add a Blossom server in settings."
        case .invalidServerURL(let url):
            return "Invalid server URL: \(url)"
        }
    }
}

/// Resolves the effective Blossom server URL for uploads.
/// Uses user-configured servers from NDKBlossomServerManager with fallback to OlasConstants defaults.
public enum BlossomServerResolver {
    /// Returns the effective server URL for uploads.
    /// - Parameter ndk: The NDK instance to query for user-configured servers
    /// - Returns: A validated URL for the upload server
    /// - Throws: `BlossomServerError.noServerConfigured` if no valid server is available
    public static func effectiveServerURL(ndk: NDK) throws -> URL {
        let blossomManager = NDKBlossomServerManager(ndk: ndk)
        var servers = blossomManager.userServers
        if servers.isEmpty {
            servers = OlasConstants.blossomServers
        }

        // Filter and find first valid server
        for rawServer in servers {
            let trimmed = rawServer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let url = URL(string: trimmed),
                  url.scheme != nil,
                  url.host != nil else {
                continue
            }

            return url
        }

        throw BlossomServerError.noServerConfigured
    }
}
