import SwiftUI
import NDKSwiftCore

public struct SettingsView: View {
    let ndk: NDK
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var blossomManager: NDKBlossomServerManager
    var sparkWalletManager: SparkWalletManager
    @ObservedObject private var settings = SettingsManager.shared

    public init(ndk: NDK, sparkWalletManager: SparkWalletManager) {
        self.ndk = ndk
        self._blossomManager = State(wrappedValue: NDKBlossomServerManager(ndk: ndk))
        self.sparkWalletManager = sparkWalletManager
    }

    public var body: some View {
        List {
            Section("Account") {
                NavigationLink(destination: AccountSettingsView()) {
                    SettingsRow(icon: "person.circle", title: "Account", color: .blue)
                }
            }

            Section("Wallet") {
                Picker("Wallet Type", selection: $settings.walletType) {
                    ForEach(WalletType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

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
            }

            Section("Privacy & Security") {
                NavigationLink(destination: PrivacySettingsView()) {
                    SettingsRow(icon: "lock.shield", title: "Privacy", color: .orange)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await authViewModel.logout() }
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
