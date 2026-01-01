// BalanceCard.swift
import SwiftUI

struct BalanceCard: View {
    let balance: Int64
    let balancesByMint: [String: Int64]
    let onDeposit: () -> Void
    let onSend: () -> Void
    var walletViewModel: WalletViewModel

    @State private var showMintBreakdown = false
    @State private var showFiat = false

    var body: some View {
        VStack(spacing: 24) {
            // Balance display
            VStack(spacing: 8) {
                Text("Balance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Tappable balance with toggle
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showFiat.toggle()
                    }
                } label: {
                    VStack(spacing: 4) {
                        if showFiat, let fiatAmount = walletViewModel.formatFiat(balance) {
                            // Show fiat value
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(fiatAmount)
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                            }

                            // Show sats as secondary
                            Text("\(formatSats(balance)) sats")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            // Show sats value
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(formatSats(balance))
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Text("sats")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }

                            // Show fiat as secondary if available
                            if let fiatAmount = walletViewModel.formatFiat(balance) {
                                Text(fiatAmount)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                // Mint breakdown toggle
                if balancesByMint.count > 1 {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            showMintBreakdown.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(balancesByMint.count) mints")
                                .font(.caption)
                            Image(systemName: showMintBreakdown ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Mint breakdown
            if showMintBreakdown {
                VStack(spacing: 8) {
                    ForEach(Array(balancesByMint.keys.sorted()), id: \.self) { mintURL in
                        if let mintBalance = balancesByMint[mintURL] {
                            HStack {
                                Text(mintDisplayName(mintURL))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(formatSats(mintBalance)) sats")
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Action buttons
            HStack(spacing: 16) {
                Button(action: onDeposit) {
                    Label("Deposit", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.glassProminent)

                Button(action: onSend) {
                    Label("Send", systemImage: "arrow.up.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.glass)
                .disabled(balance == 0)
            }
        }
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func formatSats(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func mintDisplayName(_ url: String) -> String {
        guard let url = URL(string: url) else { return url }
        return url.host ?? url.absoluteString
    }
}

