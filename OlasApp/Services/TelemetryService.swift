import Foundation
import Observation

public enum LogLevel: String, Codable, CaseIterable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    var emoji: String {
        switch self {
        case .debug: return ""
        case .info: return ""
        case .warning: return ""
        case .error: return ""
        }
    }
}

public struct LogEntry: Codable, Sendable {
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
    let metadata: [String: String]?

    var consoleOutput: String {
        let timeFormatter = ISO8601DateFormatter()
        let time = timeFormatter.string(from: timestamp)
        let meta = metadata.map { " | \($0)" } ?? ""
        return "[\(time)] [\(level.rawValue)] [\(category)] \(message)\(meta)"
    }
}

@Observable
@MainActor
public final class TelemetryService {
    public static let shared = TelemetryService()

    // Settings
    public var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "telemetryEnabled")
        }
    }

    public var endpoint: String = "" {
        didSet {
            UserDefaults.standard.set(endpoint, forKey: "telemetryEndpoint")
        }
    }

    public var minimumLevel: LogLevel = .info {
        didSet {
            UserDefaults.standard.set(minimumLevel.rawValue, forKey: "telemetryMinLevel")
        }
    }

    public var consoleLoggingEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(consoleLoggingEnabled, forKey: "telemetryConsoleEnabled")
        }
    }

    // Queued logs for batch sending
    @ObservationIgnored private var logQueue: [LogEntry] = []
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private let batchSize = 50
    @ObservationIgnored private let flushInterval: TimeInterval = 30

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "telemetryEnabled")
        self.endpoint = UserDefaults.standard.string(forKey: "telemetryEndpoint") ?? ""
        self.consoleLoggingEnabled = UserDefaults.standard.object(forKey: "telemetryConsoleEnabled") as? Bool ?? true

        if let levelString = UserDefaults.standard.string(forKey: "telemetryMinLevel"),
           let level = LogLevel(rawValue: levelString) {
            self.minimumLevel = level
        }

        startFlushTimer()
    }

    // MARK: - Logging API

    public func debug(_ message: String, category: String = "General", metadata: [String: String]? = nil) {
        log(level: .debug, message: message, category: category, metadata: metadata)
    }

    public func info(_ message: String, category: String = "General", metadata: [String: String]? = nil) {
        log(level: .info, message: message, category: category, metadata: metadata)
    }

    public func warning(_ message: String, category: String = "General", metadata: [String: String]? = nil) {
        log(level: .warning, message: message, category: category, metadata: metadata)
    }

    public func error(_ message: String, category: String = "General", metadata: [String: String]? = nil) {
        log(level: .error, message: message, category: category, metadata: metadata)
    }

    // MARK: - Core Logging

    private func log(level: LogLevel, message: String, category: String, metadata: [String: String]?) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: metadata
        )

        // Console logging
        if consoleLoggingEnabled {
            print(entry.consoleOutput)
        }

        // Skip if below minimum level or telemetry disabled
        guard isEnabled,
              shouldLog(level: level),
              !endpoint.isEmpty
        else { return }

        logQueue.append(entry)

        // Flush if batch size reached
        if logQueue.count >= batchSize {
            flush()
        }
    }

    private func shouldLog(level: LogLevel) -> Bool {
        let levels: [LogLevel] = [.debug, .info, .warning, .error]
        guard let entryIndex = levels.firstIndex(of: level),
              let minIndex = levels.firstIndex(of: minimumLevel)
        else { return false }
        return entryIndex >= minIndex
    }

    // MARK: - Batch Sending

    private func startFlushTimer() {
        sendTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.flushInterval ?? 30))
                await MainActor.run {
                    self?.flush()
                }
            }
        }
    }

    public func flush() {
        guard !logQueue.isEmpty, !endpoint.isEmpty else { return }

        let logsToSend = logQueue
        logQueue.removeAll()

        Task.detached { [endpoint] in
            await Self.sendLogs(logsToSend, to: endpoint)
        }
    }

    private static func sendLogs(_ logs: [LogEntry], to endpoint: String) async {
        guard let url = URL(string: endpoint) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(logs)

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode >= 400 {
                print("[Telemetry] Failed to send logs: HTTP \(httpResponse.statusCode)")
            }
        } catch {
            print("[Telemetry] Failed to send logs: \(error.localizedDescription)")
        }
    }

    // MARK: - Testing

    public func testConnection() async -> (success: Bool, message: String) {
        guard !endpoint.isEmpty else {
            return (false, "No endpoint configured")
        }

        guard let url = URL(string: endpoint) else {
            return (false, "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let testEntry = LogEntry(
            timestamp: Date(),
            level: .info,
            category: "Telemetry",
            message: "Connection test",
            metadata: ["test": "true"]
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode([testEntry])

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    return (true, "Connected successfully (HTTP \(httpResponse.statusCode))")
                } else {
                    return (false, "Server returned HTTP \(httpResponse.statusCode)")
                }
            }
            return (false, "Unknown response")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - Global Convenience Functions

@MainActor
public let Log = TelemetryService.shared

// Non-isolated wrapper for use outside MainActor
public func logDebug(_ message: String, category: String = "General", metadata: [String: String]? = nil) {
    Task { @MainActor in
        Log.debug(message, category: category, metadata: metadata)
    }
}

public func logInfo(_ message: String, category: String = "General", metadata: [String: String]? = nil) {
    Task { @MainActor in
        Log.info(message, category: category, metadata: metadata)
    }
}

public func logWarning(_ message: String, category: String = "General", metadata: [String: String]? = nil) {
    Task { @MainActor in
        Log.warning(message, category: category, metadata: metadata)
    }
}

public func logError(_ message: String, category: String = "General", metadata: [String: String]? = nil) {
    Task { @MainActor in
        Log.error(message, category: category, metadata: metadata)
    }
}
