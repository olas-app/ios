import BreezSdkSpark
import SwiftUI

// MARK: - Receive View (Lightning Address First per UX Guidelines)

struct ReceiveView: View {
    var walletManager: SparkWalletManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var invoice: String?
    @State private var amount: String = ""
    @State private var isGenerating = false
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Receive Method", selection: $selectedTab) {
                    Text("Lightning Address").tag(0)
                    Text("Invoice").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                ScrollView {
                    if selectedTab == 0 {
                        lightningAddressView
                    } else {
                        invoiceView
                    }
                }
            }
            .navigationTitle("Receive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Lightning Address View (Primary per UX guidelines)

    private var lightningAddressView: some View {
        VStack(spacing: 24) {
            if let address = walletManager.lightningAddress {
                // QR Code for LNURL-pay
                QRCodeView(content: "lightning:\(address)", size: 220)
                    .padding(.top, 20)

                // Address display
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(OlasTheme.Colors.zapGold)
                        Text(address)
                            .font(.body.monospaced())
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    Text("Share this address to receive payments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Action buttons
                HStack(spacing: 16) {
                    Button {
                        UIPasteboard.general.string = address
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied!" : "Copy")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OlasTheme.Colors.accent)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }

                    ShareLink(item: address) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                    }
                }
                .padding(.top, 8)

            } else {
                // No lightning address setup
                VStack(spacing: 16) {
                    Image(systemName: "bolt.badge.clock")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)

                    Text("No Lightning Address")
                        .font(.title3.bold())

                    Text("Set up a Lightning Address in settings to receive payments easily.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("You can still receive using invoices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Invoice View (Fallback)

    private var invoiceView: some View {
        VStack(spacing: 24) {
            if let invoiceString = invoice {
                invoiceDisplay(invoiceString)
            } else {
                invoiceForm
            }
        }
        .padding()
    }

    private var invoiceForm: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(OlasTheme.Colors.accent)

            Text("Create Invoice")
                .font(.title2.bold())

            Text("Generate a one-time invoice for a specific amount.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Amount (sats)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Enter amount", text: $amount)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
            }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await generateInvoice() }
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Generate Invoice")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(OlasTheme.Colors.accent)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .disabled(isGenerating)

            Spacer()
        }
    }

    private func invoiceDisplay(_ invoiceString: String) -> some View {
        VStack(spacing: 20) {
            Text("Lightning Invoice")
                .font(.title2.bold())

            QRCodeView(content: invoiceString, size: 220)

            Text(invoiceString)
                .font(.caption.monospaced())
                .lineLimit(3)
                .truncationMode(.middle)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)

            HStack(spacing: 16) {
                Button {
                    UIPasteboard.general.string = invoiceString
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(OlasTheme.Colors.accent)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }

                ShareLink(item: invoiceString) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .cornerRadius(12)
                }
            }

            Button("Generate New Invoice") {
                self.invoice = nil
            }
            .foregroundStyle(OlasTheme.Colors.accent)

            Spacer()
        }
    }

    private func generateInvoice() async {
        isGenerating = true
        defer { isGenerating = false }

        do {
            let newInvoice: String
            if let amountSats = UInt64(amount), amountSats > 0 {
                newInvoice = try await walletManager.createInvoice(amountSats: amountSats, description: nil)
            } else {
                newInvoice = try await walletManager.createOpenInvoice(description: nil)
            }
            invoice = newInvoice
        } catch {
            self.error = error.localizedDescription
        }
    }
}
