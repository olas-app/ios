// NWCSendView.swift
import SwiftUI

public struct NWCSendView: View {
    @Environment(\.dismiss) private var dismiss
    var walletManager: NWCWalletManager

    @State private var invoice: String = ""
    @State private var showScanner = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    public init(walletManager: NWCWalletManager) {
        self.walletManager = walletManager
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Balance Display
                    VStack(spacing: 8) {
                        Text("Available Balance")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(formatSats(UInt64(walletManager.balance)))
                            .font(.title.weight(.bold))
                            .foregroundStyle(OlasTheme.Colors.accent)

                        if let fiatFormatted = walletManager.formatFiat(walletManager.balance) {
                            Text("≈ \(fiatFormatted)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 24)

                    // Invoice Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lightning Invoice")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        TextField("lnbc...", text: $invoice, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.caption.monospaced())
                    }
                    .padding(.horizontal)

                    // QR Scanner Button
                    Button {
                        showScanner = true
                    } label: {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                            Text("Scan Invoice QR")
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Error/Success Messages
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }

                    if let success = successMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(success)
                                .font(.caption)
                        }
                        .foregroundStyle(.green)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }

                    // Send Button
                    Button {
                        Task {
                            await sendPayment()
                        }
                    } label: {
                        HStack {
                            if isSending {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isSending ? "Sending..." : "Send Payment")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(invoice.isEmpty || isSending ? Color(.systemGray4) : OlasTheme.Colors.zapGold)
                        .cornerRadius(12)
                    }
                    .disabled(invoice.isEmpty || isSending)
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top)
            }
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { scannedCode in
                    invoice = scannedCode
                    showScanner = false
                }
            }
        }
    }

    private func sendPayment() async {
        guard !invoice.isEmpty else { return }

        isSending = true
        errorMessage = nil
        successMessage = nil

        do {
            let response = try await walletManager.payInvoice(invoice.trimmingCharacters(in: .whitespacesAndNewlines))
            successMessage = "Payment sent! Preimage: \(response.preimage.prefix(16))..."
            invoice = ""

            // Dismiss after a short delay
            try await Task.sleep(nanoseconds: 2_000_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    private func formatSats(_ sats: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return (formatter.string(from: NSNumber(value: sats)) ?? "0") + " sats"
    }
}
