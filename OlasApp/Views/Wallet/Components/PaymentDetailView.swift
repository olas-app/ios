import BreezSdkSpark
import SwiftUI

// MARK: - Payment Detail View

struct PaymentDetailView: View {
    let payment: Payment
    @Environment(\.dismiss) private var dismiss

    @State private var showFullDetails = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Amount header
                    VStack(spacing: 8) {
                        Image(systemName: payment.paymentType == .receive ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(payment.paymentType == .receive ? .green : OlasTheme.Colors.zapGold)

                        Text("\(payment.paymentType == .receive ? "+" : "-")\(payment.amount.formattedString) sats")
                            .font(.system(size: 32, weight: .bold, design: .rounded))

                        let fees = payment.fees.formattedString
                        if fees != "0" {
                            Text("Fee: \(fees) sats")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        PaymentStatusBadge(status: payment.status)
                    }
                    .padding(.top, 20)

                    // Details section
                    VStack(alignment: .leading, spacing: 16) {
                        DetailRow(label: "Date", value: Date(timeIntervalSince1970: TimeInterval(payment.timestamp)).formatted(date: .abbreviated, time: .shortened))

                        DetailRow(label: "Method", value: payment.method.displayName)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Technical details (expandable)
                    DisclosureGroup("Technical Details", isExpanded: $showFullDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            DetailRow(label: "Payment ID", value: payment.id, isMonospace: true, isCopyable: true)
                        }
                        .padding(.top, 12)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle(payment.paymentType == .receive ? "Received Payment" : "Sent Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension PaymentMethod {
    var displayName: String {
        // PaymentMethod enum cases changed in BreezSDK - returning generic name
        return "Payment"
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var isMonospace: Bool = false
    var isCopyable: Bool = false

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(value)
                    .font(isMonospace ? .caption.monospaced() : .body)
                    .foregroundStyle(.primary)
                    .lineLimit(isMonospace ? 2 : nil)

                if isCopyable {
                    Spacer()
                    Button {
                        UIPasteboard.general.string = value
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(copied ? .green : .secondary)
                    }
                }
            }
        }
    }
}
