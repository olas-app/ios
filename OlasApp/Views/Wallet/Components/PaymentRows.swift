import BreezSdkSpark
import SwiftUI

// MARK: - Modern Payment Row

struct ModernPaymentRow: View {
    let payment: Payment
    let walletManager: SparkWalletManager

    @State private var showDetails = false

    var body: some View {
        Button {
            showDetails = true
        } label: {
            HStack(spacing: 16) {
                // Icon
                Circle()
                    .fill(iconBackground)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: payment.paymentType == .receive ? "arrow.down" : "arrow.up")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(paymentDescription)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(Date(timeIntervalSince1970: TimeInterval(payment.timestamp)).formatted(.relative(presentation: .named)))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Amount
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(payment.paymentType == .receive ? "+" : "-")\(formatFiat(payment.amount))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(payment.paymentType == .receive ? iconColor : .primary)

                    Text(formatSatsPlain(payment.amount))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetails) {
            PaymentDetailView(payment: payment)
        }
    }

    private var iconColor: Color {
        payment.paymentType == .receive ? OlasTheme.Colors.accent : .orange
    }

    private var iconBackground: Color {
        payment.paymentType == .receive ? OlasTheme.Colors.accent.opacity(0.1) : .orange.opacity(0.1)
    }

    private var paymentDescription: String {
        payment.paymentType == .receive ? "Received" : "Sent"
    }

    private func formatFiat(_ amount: U128) -> String {
        guard let sats = UInt64(amount.description) else {
            return "$0.00"
        }
        return walletManager.formatFiat(sats) ?? "$0.00"
    }

    private func formatSatsPlain(_ amount: U128) -> String {
        return amount.formattedSats
    }
}

// MARK: - Payment Row

struct PaymentRow: View {
    let payment: Payment
    let walletManager: SparkWalletManager

    @State private var showDetails = false

    var body: some View {
        Button {
            showDetails = true
        } label: {
            HStack(spacing: 12) {
                // Icon
                Circle()
                    .fill(payment.paymentType == .receive ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: payment.paymentType == .receive ? "arrow.down" : "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(payment.paymentType == .receive ? .green : .orange)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(paymentDescription)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        PaymentStatusBadge(status: payment.status)
                        Text(Date(timeIntervalSince1970: TimeInterval(payment.timestamp)).formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text("\(payment.paymentType == .receive ? "+" : "-")\(formatSats(payment.amount))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(payment.paymentType == .receive ? .green : .primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetails) {
            PaymentDetailView(payment: payment)
        }
    }

    private var paymentDescription: String {
        // PaymentDetails API changed - returning generic description for now
        return payment.paymentType == .receive ? "Received" : "Sent"
    }

    private func formatSats(_ amount: U128) -> String {
        return amount.formattedSats
    }
}

// MARK: - Payment Status Badge

struct PaymentStatusBadge: View {
    let status: PaymentStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.1))
        .cornerRadius(4)
    }

    private var statusColor: Color {
        switch status {
        case .pending: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private var statusText: String {
        switch status {
        case .pending: return "Pending"
        case .completed: return "Complete"
        case .failed: return "Failed"
        }
    }
}
