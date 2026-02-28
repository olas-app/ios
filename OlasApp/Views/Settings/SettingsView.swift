import NDKSwiftCore
import SwiftUI

public struct SettingsView: View {
    let ndk: NDK
    @Environment(NDKAuthManager.self) private var authManager
    @State private var blossomManager: NDKBlossomServerManager
    var sparkWalletManager: SparkWalletManager
    var nwcWalletManager: NWCWalletManager
    @Environment(SettingsManager.self) private var settings

    public init(ndk: NDK, sparkWalletManager: SparkWalletManager, nwcWalletManager: NWCWalletManager) {
        self.ndk = ndk
        _blossomManager = State(wrappedValue: NDKBlossomServerManager(ndk: ndk))
        self.sparkWalletManager = sparkWalletManager
        self.nwcWalletManager = nwcWalletManager
    }

    public var body: some View {
        List {
            Section("Account") {
                NavigationLink(destination: AccountSettingsView()) {
                    SettingsRow(icon: "person.circle", title: "Account", color: .blue)
                }
            }

            Section("Wallet") {
                @Bindable var settings = settings
                Picker("Wallet Type", selection: $settings.walletType) {
                    ForEach(WalletType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                switch settings.walletType {
                case .spark:
                    NavigationLink(destination: SparkWalletSettingsView(walletManager: sparkWalletManager)) {
                        HStack {
                            SettingsRow(icon: "bolt.fill", title: "Spark Wallet", color: OlasTheme.Colors.zapGold)
                            Spacer()
                            if sparkWalletManager.connectionStatus == .connected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                case .nwc:
                    NavigationLink(destination: NWCWalletSettingsView(walletManager: nwcWalletManager)) {
                        HStack {
                            SettingsRow(icon: "link", title: "NWC Wallet", color: .purple)
                            Spacer()
                            if nwcWalletManager.connectionStatus == .connected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                case .cashu:
                    HStack {
                        SettingsRow(icon: "banknote", title: "Cashu Wallet", color: .green)
                        Spacer()
                        Text("Coming Soon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("App") {
                NavigationLink(destination: AppearanceSettingsView()) {
                    SettingsRow(icon: "paintbrush", title: "Appearance", color: .purple)
                }
                NavigationLink(destination: VideoSettingsView()) {
                    SettingsRow(icon: "video", title: "Video", color: .red)
                }
                NavigationLink(destination: RelaySettingsView(ndk: ndk)) {
                    SettingsRow(icon: "network", title: "Relays", color: .green)
                }
                NavigationLink(destination: BlossomSettingsView(manager: blossomManager)) {
                    SettingsRow(icon: "externaldrive.badge.icloud", title: "Media Servers", color: .teal)
                }
                NavigationLink(destination: DeveloperToolsView(ndk: ndk)) {
                    SettingsRow(icon: "wrench.and.screwdriver", title: "Developer Tools", color: .gray)
                }
            }

            Section("Privacy & Security") {
                NavigationLink(destination: PrivacySettingsView(ndk: ndk)) {
                    SettingsRow(icon: "lock.shield", title: "Privacy", color: .orange)
                }
            }

            Section {
                Button(role: .destructive) {
                    authManager.logout()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Logout")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .cornerRadius(6)
            Text(title)
        }
    }
}
