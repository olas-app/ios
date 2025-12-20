// NWCWalletView.swift
import NDKSwiftCore
import SwiftUI

public struct NWCWalletView: View {
    var walletManager: NWCWalletManager

    @State private var showConnect = false
    @State private var showReceive = false
    @State private var showSend = false
    @State private var showSettings = false

    public init(walletManager: NWCWalletManager) {
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
            .sheet(isPresented: $showConnect) {
                NWCConnectView(walletManager: walletManager)
            }
            .sheet(isPresented: $showReceive) {
                DepositView(walletType: .nwc(walletManager))
            }
            .sheet(isPresented: $showSend) {
                NWCSendView(walletManager: walletManager)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    NWCWalletSettingsView(walletManager: walletManager)
                }
            }
        }
    }

    // MARK: - Connected View

    private var connectedView: some View {
        ScrollView {
            VStack(spacing: 32) {
                modernBalanceSection
                modernActionButtons
                modernTransactionsContainer
            }
            .padding(.top, 40)
        }
        .refreshable {
            await walletManager.refreshInfo()
        }
    }

    private var modernBalanceSection: some View {
        VStack(spacing: 16) {
            // Wallet Info
            if let info = walletManager.walletInfo {
                HStack {
                    if let alias = info.alias {
                        Text(alias)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(walletManager.connectionStatus.description)
                        .font(.caption)
                        .foregroundStyle(walletManager.connectionStatus.color)
                }
                .padding(.horizontal)
            }

            // Balance Display
            VStack(spacing: 8) {
                Text("Balance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(formatSats(UInt64(walletManager.balance)))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(OlasTheme.Colors.accent)

                if let fiatFormatted = walletManager.formatFiat(walletManager.balance) {
                    Text("≈ \(fiatFormatted)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
            .padding(.horizontal)
        }
    }

    private var modernActionButtons: some View {
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
                .background(OlasTheme.Colors.zapGold.opacity(0.1))
                .foregroundStyle(OlasTheme.Colors.zapGold)
                .cornerRadius(16)
            }
        }
        .padding(.horizontal)
    }

    private var modernTransactionsContainer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.headline)
                .padding(.horizontal)

            if walletManager.transactions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No recent transactions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(walletManager.transactions, id: \.paymentHash) { transaction in
                        NWCTransactionRow(transaction: transaction, walletManager: walletManager)
                        if transaction.paymentHash != walletManager.transactions.last?.paymentHash {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 32)
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "link.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(OlasTheme.Colors.accent)

            VStack(spacing: 8) {
                Text("Connect Your Wallet")
                    .font(.title2.bold())

                Text("Connect to any NWC-compatible Lightning wallet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let error = walletManager.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }

            Button {
                showConnect = true
            } label: {
                HStack {
                    Image(systemName: "link")
                    Text("Connect Wallet")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(OlasTheme.Colors.accent)
                .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 12) {
                Text("Compatible with:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Alby")
                    }
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Mutiny")
                    }
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Zeus")
                    }
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Any NIP-47 wallet")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }

    // MARK: - Helper Methods

    private func formatSats(_ sats: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return (formatter.string(from: NSNumber(value: sats)) ?? "0") + " sats"
    }
}

// MARK: - Transaction Row

private struct NWCTransactionRow: View {
    let transaction: NDKSwiftCore.Transaction
    let walletManager: NWCWalletManager

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: transaction.type == .incoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(transaction.type == .incoming ? .green : .orange)

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.type == .incoming ? "Received" : "Sent")
                    .font(.subheadline.weight(.medium))

                if let description = transaction.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(transaction.paymentHash.prefix(16) + "...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(formatDate(transaction.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 2) {
                    Text(transaction.type == .incoming ? "+" : "-")
                    Text(formatAmount(transaction.amount))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(transaction.type == .incoming ? .green : .primary)

                if let fiatFormatted = walletManager.formatFiat(transaction.amount / 1000) {
                    Text(fiatFormatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private func formatAmount(_ millisats: Int64) -> String {
        let sats = millisats / 1000
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return (formatter.string(from: NSNumber(value: sats)) ?? "0") + " sats"
    }

    private func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Connection Status Extension

private extension NWCConnectionStatus {
    var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case let .error(msg): return "Error: \(msg)"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return .secondary
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
}
