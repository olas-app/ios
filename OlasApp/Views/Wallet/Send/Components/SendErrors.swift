import BreezSdkSpark
import Foundation

// MARK: - Spark Send Error

/// Errors specific to the send payment flow
public enum SparkSendError: LocalizedError {
    case invalidAmount
    case insufficientFunds
    case timeout
    case networkError
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Invalid amount"
        case .insufficientFunds:
            return "Insufficient funds"
        case .timeout:
            return "Operation timed out"
        case .networkError:
            return "Network error. Please check your connection."
        case let .unknown(message):
            return message
        }
    }
}

// MARK: - Timeout Error

/// Error thrown when an operation exceeds its time limit
public enum TimeoutError: LocalizedError {
    case timedOut

    public var errorDescription: String? {
        return "Operation timed out"
    }
}

// MARK: - Error Handling Helpers

public enum SendErrorHandler {
    /// Converts various error types to user-friendly messages
    public static func userFriendlyMessage(for error: Error) -> String {
        if let sdkError = error as? SdkError {
            return sdkError.userFriendlyMessage
        }
        if let sendError = error as? SparkSendError {
            return sendError.errorDescription ?? "Unknown error"
        }
        if error is TimeoutError {
            return "Operation timed out. Please check your connection and try again."
        }
        return error.localizedDescription
    }

    /// Determines if an error is retryable
    public static func isRetryable(_ error: Error) -> Bool {
        if let sdkError = error as? SdkError {
            switch sdkError {
            case .NetworkError:
                return true
            default:
                return false
            }
        }
        return false
    }
}

// MARK: - Timeout Helper

/// Executes an async operation with a timeout
public func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError.timedOut
        }

        guard let result = try await group.next() else {
            throw TimeoutError.timedOut
        }
        group.cancelAll()
        return result
    }
}
