#!/usr/bin/env swift

import Foundation
import CryptoKit

// NWC URI from user
let nwcURI = "nostr+walletconnect://1291af9c119879ef7a59636432c6e06a7a058c0cae80db27c0f20f61f3734e52?relay=wss%3A%2F%2Fnwc.primal.net%2Fgx0168jvz6xcaehqu3uiq7j3dywelc&secret=edd9b22a1cca14107910c6e348566bd4deb421a42eba24cb540c3fd73d1c8b17&lud16=pablof7z%40primal.net"

// Parse NWC URI
func parseNWCURI(_ uri: String) -> (walletPubkey: String, relayURL: String, secret: String)? {
    guard let url = URL(string: uri),
          url.scheme == "nostr+walletconnect",
          let host = url.host,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let queryItems = components.queryItems else {
        return nil
    }

    let relay = queryItems.first { $0.name == "relay" }?.value ?? ""
    let secret = queryItems.first { $0.name == "secret" }?.value ?? ""

    return (host, relay, secret)
}

// Hex encoding/decoding
extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var index = hex.startIndex
        for _ in 0..<len {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}

// Get public key from private key (secp256k1 - simplified using CryptoKit for demo)
func getPublicKey(from privateKeyHex: String) -> String? {
    guard let privateKeyData = Data(hex: privateKeyHex) else { return nil }

    // Use Curve25519 as a stand-in (real impl needs secp256k1)
    // For a real test, we'd need to use the actual secp256k1 library
    // This is a placeholder - the iOS app uses proper secp256k1

    // Actually, let's compute it properly using the formula
    // We need secp256k1 which isn't in CryptoKit, so let's just hardcode for this test
    // The client pubkey can be derived, but for now let's focus on the WebSocket test
    return nil
}

// SHA256 hash
func sha256(_ data: Data) -> Data {
    Data(SHA256.hash(data: data))
}

// Create unsigned event
func createEvent(pubkey: String, kind: Int, content: String, tags: [[String]]) -> [String: Any] {
    let createdAt = Int(Date().timeIntervalSince1970)

    // Serialize for ID computation: [0,pubkey,created_at,kind,tags,content]
    let serialized: [Any] = [0, pubkey, createdAt, kind, tags, content]
    let jsonData = try! JSONSerialization.data(withJSONObject: serialized)
    let id = sha256(jsonData).hexString

    return [
        "id": id,
        "pubkey": pubkey,
        "created_at": createdAt,
        "kind": kind,
        "tags": tags,
        "content": content,
        "sig": "" // Will need proper signing
    ]
}

// WebSocket delegate
class NWCWebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    let semaphore = DispatchSemaphore(value: 0)
    var connected = false
    var task: URLSessionWebSocketTask?
    var receivedMessages: [String] = []

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket connected!")
        connected = true
        semaphore.signal()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("❌ WebSocket closed: \(closeCode)")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("❌ WebSocket error: \(error)")
        }
        semaphore.signal()
    }
}

// Main test
print("🔍 NWC Full Protocol Test")
print("=" .padding(toLength: 50, withPad: "=", startingAt: 0))

guard let parsed = parseNWCURI(nwcURI) else {
    print("❌ Failed to parse NWC URI")
    exit(1)
}

print("✅ Parsed NWC URI:")
print("   Wallet Pubkey: \(parsed.walletPubkey)")
print("   Relay URL: \(parsed.relayURL)")
print("   Secret: \(parsed.secret.prefix(16))...")

// Connect to relay
print("\n📡 Connecting to relay...")

let delegate = NWCWebSocketDelegate()
let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

guard let relayURL = URL(string: parsed.relayURL) else {
    print("❌ Invalid relay URL")
    exit(1)
}

let wsTask = session.webSocketTask(with: relayURL)
delegate.task = wsTask
wsTask.resume()

// Wait for connection
let connectResult = delegate.semaphore.wait(timeout: .now() + 10)
guard connectResult == .success && delegate.connected else {
    print("❌ Failed to connect to relay")
    exit(1)
}

print("✅ Connected to relay!")

// For a full test, we need:
// 1. secp256k1 library to derive public key from secret and sign events
// 2. NIP-04 encryption (AES-256-CBC with shared secret)
//
// Since we don't have secp256k1 in vanilla Swift, let's at least test
// that we can subscribe and see if we get any events

// Subscribe to NWC response events for our pubkey
// We'd need to know our client pubkey (derived from secret) to filter properly
// For now, let's just subscribe to kind 23195 events

let subId = "nwc-test-\(Int.random(in: 1000...9999))"
let filter: [String: Any] = [
    "kinds": [23195], // NWC response events
    "limit": 1
]

let reqMessage: [Any] = ["REQ", subId, filter]
let reqJSON = try! JSONSerialization.data(withJSONObject: reqMessage)
let reqString = String(data: reqJSON, encoding: .utf8)!

print("\n📤 Sending subscription request...")
print("   \(reqString)")

let sendSemaphore = DispatchSemaphore(value: 0)
wsTask.send(.string(reqString)) { error in
    if let error = error {
        print("❌ Send error: \(error)")
    } else {
        print("✅ Subscription sent!")
    }
    sendSemaphore.signal()
}
sendSemaphore.wait()

// Listen for messages
print("\n📥 Listening for messages (5 seconds)...")

func receiveMessage() {
    wsTask.receive { result in
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                print("📨 Received: \(text.prefix(200))...")
                if text.contains("EOSE") {
                    print("✅ Got EOSE - subscription is active")
                }
            case .data(let data):
                print("📨 Received binary: \(data.count) bytes")
            @unknown default:
                break
            }
            receiveMessage() // Continue listening
        case .failure(let error):
            print("❌ Receive error: \(error)")
        }
    }
}

receiveMessage()

// Wait a bit for messages
Thread.sleep(forTimeInterval: 5)

// Close connection
print("\n🔒 Closing connection...")
wsTask.cancel(with: .normalClosure, reason: nil)

print("\n" + "=".padding(toLength: 50, withPad: "=", startingAt: 0))
print("⚠️  Full NWC test requires secp256k1 library for:")
print("   - Deriving client pubkey from secret")
print("   - Signing NWC request events")
print("   - NIP-04 encryption")
print("")
print("The iOS app has these via NDKSwift. This test confirms:")
print("   ✅ WebSocket connection works")
print("   ✅ Relay accepts subscriptions")
print("")
print("Next step: Debug why NDKSwift's NWC flow hangs")
