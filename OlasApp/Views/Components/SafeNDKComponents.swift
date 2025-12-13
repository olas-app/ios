import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

// MARK: - Safe NDK UI Component Wrappers

// These wrappers handle optional NDK gracefully, eliminating force unwraps

/// Safe wrapper for NDKUIDisplayName that handles optional NDK
struct SafeDisplayName: View {
    @Environment(\.ndk) private var ndk
    let pubkey: String

    var body: some View {
        if let ndk {
            NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
        } else {
            Text(String(pubkey.prefix(16)) + "...")
                .redacted(reason: .placeholder)
        }
    }
}

/// Safe wrapper for NDKUIProfilePicture that handles optional NDK
struct SafeProfilePicture: View {
    @Environment(\.ndk) private var ndk
    let pubkey: String
    let size: CGFloat

    var body: some View {
        if let ndk {
            NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: size)
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                )
        }
    }
}

/// Safe wrapper for NDKUIFollowButton that handles optional NDK
struct SafeFollowButton: View {
    @Environment(\.ndk) private var ndk
    let pubkey: String
    let style: NDKUIFollowButton.ButtonStyle

    var body: some View {
        if let ndk {
            NDKUIFollowButton(ndk: ndk, pubkey: pubkey, style: style)
        } else {
            Button("Follow") {}
                .disabled(true)
                .buttonStyle(.bordered)
        }
    }
}

/// Safe wrapper for ZapButton that handles optional NDK
struct SafeZapButton: View {
    @Environment(\.ndk) private var ndk
    let event: NDKEvent

    var body: some View {
        if let ndk {
            ZapButton(event: event, ndk: ndk)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                Text("0")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
