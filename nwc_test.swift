#!/usr/bin/env swift

import Foundation

// Test NWC URI parsing
let nwcURI = "nostr+walletconnect://1291af9c119879ef7a59636432c6e06a7a058c0cae80db27c0f20f61f3734e52?relay=wss%3A%2F%2Fnwc.primal.net%2Fgx0168jvz6xcaehqu3uiq7j3dywelc&secret=edd9b22a1cca14107910c6e348566bd4deb421a42eba24cb540c3fd73d1c8b17&lud16=pablof7z%40primal.net"

print("Testing NWC URI parsing...")
print("Input URI: \(nwcURI)")

guard let url = URL(string: nwcURI) else {
    print("ERROR: Failed to parse URL")
    exit(1)
}

print("\nURL components:")
print("  Scheme: \(url.scheme ?? "nil")")
print("  Host: \(url.host ?? "nil")")
print("  Path: \(url.path)")

guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
    print("ERROR: Failed to get URL components")
    exit(1)
}

print("\nQuery items:")
for item in components.queryItems ?? [] {
    print("  \(item.name): \(item.value ?? "nil")")
}

// Extract relay URL
let relayURLEncoded = components.queryItems?.first(where: { $0.name == "relay" })?.value ?? ""
print("\nRelay URL (from query): \(relayURLEncoded)")

// Test URL normalization
func normalizeRelayURL(_ url: String) -> String {
    var result = url.trimmingCharacters(in: .whitespacesAndNewlines)

    // Ensure wss:// prefix
    if !result.hasPrefix("wss://") && !result.hasPrefix("ws://") {
        result = "wss://\(result)"
    }

    // Ensure trailing slash
    if !result.hasSuffix("/") {
        result = "\(result)/"
    }

    return result
}

let normalizedRelay = normalizeRelayURL(relayURLEncoded)
print("Normalized relay URL: \(normalizedRelay)")

// Test WebSocket connection to the relay
print("\n--- Testing WebSocket connection to relay ---")

class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    let semaphore = DispatchSemaphore(value: 0)
    var connected = false
    var error: Error?

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket connected!")
        connected = true
        semaphore.signal()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("WebSocket closed with code: \(closeCode)")
        semaphore.signal()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("WebSocket error: \(error)")
            self.error = error
        }
        semaphore.signal()
    }
}

let delegate = WebSocketDelegate()
let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

guard let wsURL = URL(string: normalizedRelay) else {
    print("ERROR: Invalid WebSocket URL")
    exit(1)
}

print("Connecting to: \(wsURL)")
let wsTask = session.webSocketTask(with: wsURL)
wsTask.resume()

// Wait for connection (up to 10 seconds)
let result = delegate.semaphore.wait(timeout: .now() + 10)
if result == .timedOut {
    print("ERROR: Connection timed out after 10 seconds")
    wsTask.cancel()
    exit(1)
}

if delegate.connected {
    print("SUCCESS: WebSocket connection established!")

    // Try to send a simple Nostr message (REQ for info)
    let reqMessage = "[\"REQ\",\"test\",{\"kinds\":[0],\"limit\":1}]"
    print("\nSending test message: \(reqMessage)")

    wsTask.send(.string(reqMessage)) { error in
        if let error = error {
            print("Send error: \(error)")
        } else {
            print("Message sent successfully")
        }
    }

    // Wait for response
    wsTask.receive { result in
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                print("Received: \(text.prefix(200))...")
            case .data(let data):
                print("Received data: \(data.count) bytes")
            @unknown default:
                print("Unknown message type")
            }
        case .failure(let error):
            print("Receive error: \(error)")
        }
        delegate.semaphore.signal()
    }

    _ = delegate.semaphore.wait(timeout: .now() + 5)

    wsTask.cancel(with: .goingAway, reason: nil)
} else {
    print("ERROR: Failed to connect")
    if let error = delegate.error {
        print("Error details: \(error)")
    }
    exit(1)
}

print("\n--- Test complete ---")
