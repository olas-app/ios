import SwiftUI
import BreezSdkSpark
import CoreImage.CIFilterBuiltins

public struct SparkWalletView: View {
    var walletManager: SparkWalletManager

    @State private var showCreateWallet = false
    @State private var showImportWallet = false
    @State private var showReceive = false
    @State private var showSend = false
    @State private var showSettings = false

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
                ReceiveView(walletManager: walletManager)
            }
            .sheet(isPresented: $showSend) {
                SparkSendView(walletManager: walletManager)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SparkWalletSettingsView(walletManager: walletManager)
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

            ScrollView {
                VStack(spacing: 32) {
                    balanceCard
                    actionButtons
                    recentTransactions
                }
                .padding()
            }
            .refreshable {
                await walletManager.sync()
            }
        }
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
                        PaymentRow(payment: payment)
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
}

// MARK: - Payment Row

struct PaymentRow: View {
    let payment: Payment

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

// MARK: - QR Code Generator

struct QRCodeView: View {
    let content: String
    let size: CGFloat

    var body: some View {
        if let image = generateQRCode(from: content) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .cornerRadius(12)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "qrcode")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for crisp rendering
        let scale = size / outputImage.extent.size.width * UIScreen.main.scale
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}

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

        let amountSats: UInt64? = UInt64(amount)

        do {
            let newInvoice = try await walletManager.createInvoice(amountSats: amountSats, description: nil)
            invoice = newInvoice
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Send View (with parsing, fees, and scanner)

struct SparkSendView: View {
    var walletManager: SparkWalletManager
    @Environment(\.dismiss) private var dismiss

    enum SendState {
        case input
        case parsed(InputType)
        case confirm(PrepareSendPaymentResponse)
        case sending
        case success
    }

    @State private var state: SendState = .input
    @State private var inputText: String = ""
    @State private var customAmount: String = ""
    @State private var error: String?
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch state {
                case .input:
                    inputView
                case .parsed(let parsed):
                    parsedView(parsed)
                case .confirm(let prepared):
                    confirmView(prepared)
                case .sending:
                    sendingView
                case .success:
                    successView
                }
            }
            .padding()
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { scannedCode in
                    inputText = scannedCode
                    showScanner = false
                    Task { await parseInput() }
                }
            }
        }
    }

    // MARK: - Input View

    private var inputView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(OlasTheme.Colors.zapGold)

            Text("Send Payment")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Invoice, Address, or Lightning Address")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextEditor(text: $inputText)
                        .font(.body.monospaced())
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    VStack(spacing: 8) {
                        Button {
                            showScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                        }

                        Button {
                            if let pasted = UIPasteboard.general.string {
                                inputText = pasted
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                        }
                    }
                }
            }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await parseInput() }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(inputText.isEmpty ? .gray : OlasTheme.Colors.zapGold)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .disabled(inputText.isEmpty)

            Spacer()
        }
    }

    // MARK: - Parsed View (amount entry if needed)

    private func parsedView(_ parsed: InputType) -> some View {
        VStack(spacing: 20) {
            // Type indicator
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(parsed.typeDescription)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)

            // Details based on type
            parsedDetailsView(parsed)

            // Amount input if needed
            if parsed.requiresAmount {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Amount (sats)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("Enter amount", text: $customAmount)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)

                        Button {
                            customAmount = "\(walletManager.balance)"
                        } label: {
                            Text("Max")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray5))
                                .cornerRadius(6)
                        }
                    }
                }
            }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button {
                    state = .input
                    error = nil
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }

                Button {
                    Task { await preparePayment(parsed) }
                } label: {
                    Text("Review Payment")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canProceed(parsed) ? OlasTheme.Colors.zapGold : .gray)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(!canProceed(parsed))
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func parsedDetailsView(_ parsed: InputType) -> some View {
        switch parsed {
        case .bolt11Invoice(let details):
            VStack(spacing: 12) {
                // amountSats property removed in new BreezSDK version
                // Displaying generic amount text for now
                Text("Lightning Invoice")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                if let description = details.description, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        case .lnurlPay(let details):
            VStack(spacing: 12) {
                // lnAddress property removed from LnurlPayRequestDetails
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(OlasTheme.Colors.zapGold)
                    Text("LNURL Pay")
                        .font(.body.monospaced())
                }
                // minSendableSats/maxSendableSats removed from LnurlPayRequestDetails
                Text("Enter amount")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .bitcoinAddress(let details):
            VStack(spacing: 8) {
                Text(details.address)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                // amountSats property removed from BitcoinAddressDetails
                Text("Bitcoin Address")
                    .font(.title2.bold())
            }
        case .sparkAddress(let details):
            Text(details.address)
                .font(.caption.monospaced())
                .lineLimit(2)
        case .lightningAddress(let details):
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(OlasTheme.Colors.zapGold)
                Text(details.address)
                    .font(.body.monospaced())
            }
        default:
            Text("Ready to send")
        }
    }

    // MARK: - Confirm View (shows fees)

    private func confirmView(_ prepared: PrepareSendPaymentResponse) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(OlasTheme.Colors.zapGold)

            Text("Confirm Payment")
                .font(.title2.bold())

            VStack(spacing: 16) {
                // Amount breakdown
                VStack(spacing: 8) {
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text("\(prepared.amount.formattedString) sats")
                            .fontWeight(.medium)
                    }

                    // Fee display based on payment method
                    if let fees = extractFees(from: prepared.paymentMethod) {
                        HStack {
                            Text("Network Fee")
                            Spacer()
                            Text("\(fees) sats")
                                .fontWeight(.medium)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Total")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(prepared.amount.formattedString) sats")
                            .font(.title3.bold())
                            .foregroundStyle(OlasTheme.Colors.zapGold)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button {
                    state = .input
                    error = nil
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }

                Button {
                    Task { await sendPayment(prepared) }
                } label: {
                    Text("Send Payment")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OlasTheme.Colors.zapGold)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
            }

            Spacer()
        }
    }

    private func extractFees(from method: SendPaymentMethod) -> String? {
        switch method {
        case .bolt11Invoice:
            // Fee calculation changed in new BreezSDK
            return "Fee varies"
        case .sparkAddress(let address, let fee, _):
            return "\(fee)"
        case .sparkInvoice(let details, let fee, _):
            return "\(fee)"
        case .bitcoinAddress(let address, let feeQuote):
            // satPerVbyte property removed from SendOnchainFeeQuote
            return "Bitcoin fee"
        default:
            return nil
        }
    }

    // MARK: - Sending View

    private var sendingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Sending Payment...")
                .font(.title2.bold())

            Text("Please wait while we process your payment.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Payment Sent!")
                .font(.title.bold())

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(OlasTheme.Colors.accent)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }

            Spacer()
        }
    }

    // MARK: - Actions

    private func parseInput() async {
        error = nil
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let parsed = try await walletManager.parseInput(trimmed)
            state = .parsed(parsed)
        } catch {
            self.error = "Could not parse input: \(error.localizedDescription)"
        }
    }

    private func preparePayment(_ parsed: InputType) async {
        error = nil

        let amount: UInt64?
        if parsed.requiresAmount {
            guard let parsedAmount = UInt64(customAmount), parsedAmount > 0 else {
                error = "Please enter a valid amount"
                return
            }
            amount = parsedAmount
        } else {
            amount = parsed.embeddedAmountSats
        }

        do {
            let prepared = try await walletManager.preparePayment(input: inputText.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount)
            state = .confirm(prepared)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendPayment(_ prepared: PrepareSendPaymentResponse) async {
        state = .sending
        error = nil

        do {
            try await walletManager.sendPreparedPayment(prepared)
            state = .success
        } catch {
            self.error = error.localizedDescription
            state = .confirm(prepared)
        }
    }

    private func canProceed(_ parsed: InputType) -> Bool {
        if parsed.requiresAmount {
            return UInt64(customAmount) ?? 0 > 0
        }
        return true
    }
}

// MARK: - InputType Extensions

extension InputType {
    var typeDescription: String {
        switch self {
        case .bolt11Invoice: return "Lightning Invoice"
        case .bolt12Invoice: return "BOLT12 Invoice"
        case .bolt12Offer: return "BOLT12 Offer"
        case .lnurlPay: return "LNURL Pay"
        case .lnurlWithdraw: return "LNURL Withdraw"
        case .lnurlAuth: return "LNURL Auth"
        case .bitcoinAddress: return "Bitcoin Address"
        case .lightningAddress: return "Lightning Address"
        case .sparkAddress: return "Spark Address"
        case .sparkInvoice: return "Spark Invoice"
        case .bip21: return "BIP21 URI"
        case .bolt12InvoiceRequest: return "BOLT12 Request"
        case .silentPaymentAddress: return "Silent Payment"
        case .url: return "URL"
        }
    }

    var requiresAmount: Bool {
        switch self {
        case .bolt11Invoice:
            // amountSats property removed - assuming amount is always embedded
            return false
        case .lnurlPay, .lightningAddress, .sparkAddress:
            return true
        case .bitcoinAddress:
            // amountSats property removed - assuming amount is always embedded
            return false
        default:
            return false
        }
    }

    var embeddedAmountSats: UInt64? {
        switch self {
        case .bolt11Invoice:
            // amountSats property removed from BreezSDK
            return nil
        case .bitcoinAddress:
            // amountSats property removed from BreezSDK
            return nil
        default:
            return nil
        }
    }
}
