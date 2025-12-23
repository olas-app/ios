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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    heroSection
                        .frame(minHeight: geometry.size.height - geometry.safeAreaInsets.top - 60)
                    transactionsSection
                }
            }
            .refreshable {
                await walletManager.refreshInfo()
            }
        }
        .background(Color(.systemBackground))
        .task {
            await walletManager.refreshInfo()
        }
    }

    private var heroSection: some View {
        VStack(spacing: 32) {
            // Balance display
            VStack(spacing: 8) {
                AnimatedBalanceView(
                    balance: walletManager.balance,
                    fontSize: 56,
                    color: .primary
                )

                if let fiatFormatted = walletManager.formatFiat(walletManager.balance) {
                    Text("≈ \(fiatFormatted)")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 24)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    showReceive = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Receive")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showSend = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Send")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)

            if walletManager.isLoading {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            if walletManager.transactions.isEmpty {
                emptyTransactionsView
            } else {
                transactionsList
            }
        }
    }

    private var emptyTransactionsView: some View {
        VStack(spacing: 8) {
            Text("No transactions yet")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var transactionsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(walletManager.transactions.enumerated()), id: \.offset) { index, transaction in
                NWCTransactionRow(transaction: transaction, walletManager: walletManager)
                if index < walletManager.transactions.count - 1 {
                    Divider()
                        .padding(.leading, 56)
                }
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
                } else if let paymentHash = transaction.paymentHash {
                    Text(paymentHash.prefix(16) + "...")
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
