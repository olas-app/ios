import BreezSdkSpark
import SwiftUI

public struct SparkWalletView: View {
    var walletManager: SparkWalletManager

    @State private var showCreateWallet = false
    @State private var showImportWallet = false
    @State private var showReceive = false
    @State private var showSend = false
    @State private var showSettings = false
    @State private var showLightningAddressQR = false
    @State private var isBackupReminderDismissed = false

    public init(walletManager: SparkWalletManager) {
        self.walletManager = walletManager
    }

    public var body: some View {
        NavigationStack {
            Group {
                if walletManager.connectionStatus == .connected {
                    connectedView
                } else {
                    setupView
                }
            }
            .navigationTitle("Wallet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if walletManager.connectionStatus == .connected {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateWallet) {
                CreateSparkWalletView(walletManager: walletManager)
            }
            .sheet(isPresented: $showImportWallet) {
                ImportSparkWalletView(walletManager: walletManager)
            }
            .sheet(isPresented: $showReceive) {
                DepositView(walletType: .spark(walletManager))
            }
            .sheet(isPresented: $showSend) {
                SparkSendView(walletManager: walletManager)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SparkWalletSettingsView(walletManager: walletManager)
                }
            }
            .sheet(isPresented: $showLightningAddressQR) {
                if let address = walletManager.lightningAddress {
                    LightningAddressQRView(address: address)
                }
            }
        }
    }

    // MARK: - Connected View

    private var connectedView: some View {
        VStack(spacing: 0) {
            if walletManager.networkStatus.isOffline {
                offlineBanner
            }

            if !hasBackedUpWallet && !isBackupReminderDismissed {
                backupReminderBanner
            }

            ScrollView {
                VStack(spacing: 32) {
                    modernBalanceSection
                    modernActionButtons
                    modernTransactionsContainer
                }
                .padding(.top, 40)
            }
            .refreshable {
                await walletManager.sync()
            }
        }
    }

    private var hasBackedUpWallet: Bool {
        UserDefaults.standard.bool(forKey: "hasBackedUpSparkWallet")
    }

    private var backupReminderBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundStyle(.orange)

            Text("Remember to backup your wallet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                showSettings = true
            } label: {
                Text("Backup")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(OlasTheme.Colors.accent)
                    .cornerRadius(8)
            }

            Button {
                isBackupReminderDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.15))
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption)
            Text("No Internet Connection")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.orange)
    }

    private var balanceCard: some View {
        VStack(spacing: 12) {
            Text("Balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(formatSats(walletManager.balance))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(OlasTheme.Colors.accent)

            if let address = walletManager.lightningAddress {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(OlasTheme.Colors.zapGold)
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if walletManager.isLoading {
                ProgressView()
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 20) {
            Button {
                showReceive = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 32))
                    Text("Receive")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(OlasTheme.Colors.accent.opacity(0.1))
                .foregroundStyle(OlasTheme.Colors.accent)
                .cornerRadius(16)
            }

            Button {
                showSend = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                    Text("Send")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(walletManager.networkStatus.isOffline ? Color(.systemGray4).opacity(0.1) : OlasTheme.Colors.zapGold.opacity(0.1))
                .foregroundStyle(walletManager.networkStatus.isOffline ? .secondary : OlasTheme.Colors.zapGold)
                .cornerRadius(16)
            }
            .disabled(walletManager.networkStatus.isOffline)
        }
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)

            if walletManager.payments.isEmpty {
                VStack(spacing: 8) {
                    Text("No recent transactions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                }
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(walletManager.payments, id: \.id) { payment in
                        PaymentRow(payment: payment, walletManager: walletManager)
                        if payment.id != walletManager.payments.last?.id {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
            }
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bolt.fill")
                .font(.system(size: 80))
                .foregroundStyle(OlasTheme.Colors.zapGold)

            Text("Spark Wallet")
                .font(.title.bold())

            Text("Self-custodial Bitcoin Lightning wallet. Your keys, your coins.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if walletManager.connectionStatus == .connecting {
                ProgressView("Connecting...")
                    .padding()
            }

            if let error = walletManager.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button {
                    showCreateWallet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create New Wallet")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(OlasTheme.Colors.accent)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }

                Button {
                    showImportWallet = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Import Existing Wallet")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            .padding(.top, 20)

            Spacer()
        }
        .padding()
    }

    private func formatSats(_ amount: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "\(formatted) sats"
    }

    private func formatFiat(_ amount: UInt64) -> String {
        walletManager.formatFiat(amount) ?? "$0.00"
    }

    // MARK: - Modern Components

    private var modernBalanceSection: some View {
        VStack(spacing: 16) {
            // Fiat amount (large)
            Text(formatFiat(walletManager.balance))
                .font(.system(size: 56, weight: .light, design: .rounded))
                .foregroundStyle(.primary)

            // Sats amount (smaller)
            Text(formatSats(walletManager.balance))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            if let address = walletManager.lightningAddress {
                Button {
                    showLightningAddressQR = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(OlasTheme.Colors.zapGold)
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "qrcode")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if walletManager.isLoading {
                ProgressView()
                    .tint(.primary)
                    .padding(.top, 8)
            }
        }
        .padding(.vertical, 20)
    }

    private var modernActionButtons: some View {
        HStack(spacing: 16) {
            Button {
                showReceive = true
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 24, weight: .medium))
                    Text("Receive")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Button {
                showSend = true
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 24, weight: .medium))
                    Text("Send")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(walletManager.networkStatus.isOffline)
            .opacity(walletManager.networkStatus.isOffline ? 0.5 : 1.0)
        }
        .padding(.horizontal, 20)
    }

    private var modernTransactionsContainer: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Activity")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)

            // Transactions list
            if walletManager.payments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No transactions yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(walletManager.payments, id: \.id) { payment in
                        ModernPaymentRow(payment: payment, walletManager: walletManager)
                        if payment.id != walletManager.payments.last?.id {
                            Divider()
                                .padding(.leading, 68)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
