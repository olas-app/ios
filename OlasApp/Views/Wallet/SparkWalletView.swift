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
                ModernReceiveView(walletManager: walletManager)
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
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(OlasTheme.Colors.zapGold)
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

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

// MARK: - Send View (Modern UX with animations, haptics, and polish)

struct SparkSendView: View {
    var walletManager: SparkWalletManager
    @Environment(\.dismiss) private var dismiss

    enum SendState: Equatable {
        case scanning
        case manualInput
        case parsing
        case parsed(InputType)
        case preparing
        case confirm(PrepareSendPaymentResponse)
        case sending
        case success(paymentHash: String?, feePaid: UInt64?)
        case error(String)

        static func == (lhs: SendState, rhs: SendState) -> Bool {
            switch (lhs, rhs) {
            case (.scanning, .scanning),
                 (.manualInput, .manualInput),
                 (.parsing, .parsing),
                 (.preparing, .preparing),
                 (.sending, .sending):
                return true
            case (.parsed(let a), .parsed(let b)):
                return type(of: a) == type(of: b)
            case (.confirm, .confirm):
                return true
            case (.success, .success):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @State private var state: SendState = .scanning
    @State private var manualInput: String = ""
    @State private var amountSats: String = ""
    @State private var showFlash = false
    @State private var originalInput: String = ""

    var body: some View {
        ZStack {
            // Main content
            Group {
                switch state {
                case .scanning:
                    scannerView
                case .manualInput:
                    manualInputView
                case .parsing:
                    parsingView
                case .parsed(let inputType):
                    parsedView(inputType: inputType)
                case .preparing:
                    preparingView
                case .confirm(let prepared):
                    confirmView(prepared: prepared)
                case .sending:
                    sendingView
                case .success(let hash, let fee):
                    successView(paymentHash: hash, feePaid: fee)
                case .error(let message):
                    errorView(message: message)
                }
            }
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .opacity
            ))

            // Flash overlay
            if showFlash {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: state)
        .animation(.easeOut(duration: 0.3), value: showFlash)
    }

    // MARK: - Scanner View

    private var scannerView: some View {
        ZStack {
            // Camera view
            QRCameraView { code in
                handleScannedCode(code)
            }
            .ignoresSafeArea()

            // Scanning line
            ScanningLineView()

            // Corner brackets
            ScannerFrameView()

            // Instructions and button
            VStack {
                Spacer()

                Text("Point at QR code or Lightning Address")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()

                Button {
                    triggerHaptic(.medium)
                    transitionTo(.manualInput)
                } label: {
                    Text("Enter Manually")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .accessibilityLabel("Enter payment details manually")
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .background(Circle().fill(.black.opacity(0.3)))
                    }
                    .padding()
                    .accessibilityLabel("Close")
                }
                Spacer()
            }
        }
        .background(Color.black)
        .onAppear {
            triggerHaptic(.light)
        }
    }

    // MARK: - Manual Input View

    private var manualInputView: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter Lightning Invoice or Address")
                    .font(.headline)
                    .padding(.top)

                TextEditor(text: $manualInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .accessibilityLabel("Payment input field")

                HStack(spacing: 16) {
                    Button {
                        triggerHaptic(.light)
                        if let clipboard = UIPasteboard.general.string {
                            manualInput = clipboard
                        }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.2))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Paste from clipboard")

                    Button {
                        Task {
                            await parseInput(manualInput)
                        }
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(OlasTheme.Colors.zapGold)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(manualInput.isEmpty)
                    .accessibilityLabel("Continue with payment")
                }
                .padding(.horizontal)

                Spacer()

                Button {
                    triggerHaptic(.light)
                    transitionTo(.scanning)
                } label: {
                    Label("Back to Camera", systemImage: "camera")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .accessibilityLabel("Return to camera scanner")
            }
            .navigationTitle("Manual Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Parsing View

    private var parsingView: some View {
        VStack(spacing: 24) {
            PulsingBoltIcon()

            Text("Validating Payment...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Validating payment information")
    }

    // MARK: - Parsed View

    @ViewBuilder
    private func parsedView(inputType: InputType) -> some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Checkmark with bounce
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(OlasTheme.Colors.success)
                    .scaleEffect(1.0)
                    .onAppear {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.1)) {
                            // Bounce handled by transition
                        }
                    }
                    .accessibilityLabel("Payment validated successfully")

                // Show parsed info
                VStack(spacing: 16) {
                    switch inputType {
                    case .bolt11Invoice(let invoice):
                        parsedInvoiceInfo(invoice)
                    case .lightningAddress(let address):
                        parsedAddressInfo(address)
                    default:
                        Text("Unsupported payment type")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Spacer()

                // Continue button
                Button {
                    triggerHaptic(.heavy)
                    Task {
                        await preparePayment(inputType: inputType)
                    }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OlasTheme.Colors.zapGold)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .accessibilityLabel("Continue to payment confirmation")
            }
            .navigationTitle("Payment Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func parsedInvoiceInfo(_ invoice: some Any) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let amountMsat = (invoice as AnyObject).value(forKey: "amountMsat") as? UInt64 {
                HStack {
                    Text("Amount:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(amountMsat / 1000) sats")
                        .font(.headline)
                }

                if let description = (invoice as AnyObject).value(forKey: "description") as? String,
                   !description.isEmpty {
                    HStack(alignment: .top) {
                        Text("Description:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(description)
                            .font(.subheadline)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } else {
                Text("Lightning Invoice")
                    .font(.headline)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lightning invoice details")
    }

    @ViewBuilder
    private func parsedAddressInfo(_ address: some Any) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let addressString = (address as AnyObject).value(forKey: "lightningAddress") as? String {
                HStack {
                    Text("Address:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(addressString)
                        .font(.subheadline.monospaced())
                }
            }

            // Amount entry
            VStack(alignment: .leading, spacing: 8) {
                Text("Amount (sats)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("0", text: $amountSats)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .keyboardType(.numberPad)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Enter amount in satoshis")
                    .onChange(of: amountSats) {
                        triggerHaptic(.light)
                    }
            }
        }
    }

    // MARK: - Preparing View

    private var preparingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Preparing Payment...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing payment")
    }

    // MARK: - Confirm View

    private func confirmView(prepared: PrepareSendPaymentResponse) -> some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Amount display with counter animation
                VStack(spacing: 8) {
                    Text("Sending")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Confirm Payment")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(OlasTheme.Colors.zapGold)
                }
                .padding()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Confirm payment")

                // Fee info
                VStack(spacing: 16) {
                    Text("Review payment details and confirm to send")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Spacer()

                // Send button
                Button {
                    triggerHaptic(.heavy)
                    Task {
                        await sendPayment(prepared: prepared)
                    }
                } label: {
                    Text("Send Payment")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OlasTheme.Colors.zapGold)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(false)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .accessibilityLabel("Confirm and send payment")
            }
            .navigationTitle("Confirm Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .scaleEffect(1.0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                // Scale handled by transition
            }
        }
    }

    // MARK: - Sending View

    private var sendingView: some View {
        VStack(spacing: 24) {
            ZStack {
                // Rotating bolt
                Image(systemName: "bolt.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(OlasTheme.Colors.zapGold)
                    .rotationEffect(.degrees(0))
                    .modifier(RotatingBoltModifier())

                // Pulsing circle
                Circle()
                    .stroke(OlasTheme.Colors.zapGold.opacity(0.3), lineWidth: 2)
                    .frame(width: 100, height: 100)
                    .scaleEffect(1.0)
                    .modifier(PulsingScaleModifier())
            }

            Text("Sending Payment...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sending payment in progress")
    }

    // MARK: - Success View

    private func successView(paymentHash: String?, feePaid: UInt64?) -> some View {
        VStack(spacing: 32) {
            // Multi-phase bounce animation
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 96))
                .foregroundStyle(OlasTheme.Colors.success)
                .scaleEffect(1.0)
                .modifier(SuccessBounceModifier())

            VStack(spacing: 8) {
                Text("Payment Sent!")
                    .font(.title2.bold())

                if let fee = feePaid, fee > 0 {
                    Text("Fee: \(fee) sats")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Payment sent successfully" + (feePaid.map { ", fee \($0) satoshis" } ?? ""))

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(OlasTheme.Colors.success)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .accessibilityLabel("Close payment view")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            triggerNotificationHaptic(.success)
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Shaking error icon
                ShakingErrorIcon()
                    .accessibilityLabel("Error occurred")

                VStack(spacing: 12) {
                    Text("Payment Failed")
                        .font(.title2.bold())

                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Payment failed. \(message)")

                Spacer()

                // Action buttons
                VStack(spacing: 16) {
                    Button {
                        triggerHaptic(.medium)
                        transitionTo(.scanning)
                    } label: {
                        Text("Try Again")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(OlasTheme.Colors.zapGold)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityLabel("Try payment again")

                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.2))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityLabel("Cancel and close")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .navigationTitle("Error")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            triggerNotificationHaptic(.error)
        }
    }

    // MARK: - Actions

    private func handleScannedCode(_ code: String) {
        // Flash effect
        withAnimation(.easeOut(duration: 0.3)) {
            showFlash = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.3)) {
                showFlash = false
            }
        }

        // Success haptic
        triggerNotificationHaptic(.success)

        // Parse input
        Task {
            await parseInput(code)
        }
    }

    private func parseInput(_ input: String) async {
        transitionTo(.parsing)

        var cleanedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle lightning: prefix
        if cleanedInput.lowercased().hasPrefix("lightning:") {
            cleanedInput = String(cleanedInput.dropFirst(10))
        }

        // Store original input for later use
        originalInput = cleanedInput

        do {
            // Add timeout
            let inputType = try await withTimeout(seconds: 10) {
                try await walletManager.parseInput(cleanedInput)
            }

            transitionTo(.parsed(inputType))

        } catch {
            let errorMessage = handleError(error)
            transitionTo(.error(errorMessage))
        }
    }

    private func preparePayment(inputType: InputType) async {
        transitionTo(.preparing)

        do {
            // Determine amount
            let amount: UInt64?
            switch inputType {
            case .lightningAddress:
                guard let sats = UInt64(amountSats), sats > 0 else {
                    throw SparkSendError.invalidAmount
                }
                amount = sats
            default:
                amount = nil
            }

            // Get original input string
            let inputString = getInputString(inputType)

            // Add timeout
            let prepared = try await withTimeout(seconds: 10) {
                try await walletManager.preparePayment(input: inputString, amount: amount)
            }

            transitionTo(.confirm(prepared))

        } catch {
            let errorMessage = handleError(error)
            transitionTo(.error(errorMessage))
        }
    }

    private func sendPayment(prepared: PrepareSendPaymentResponse) async {
        transitionTo(.sending)

        do {
            // Add timeout
            try await withTimeout(seconds: 30) {
                try await walletManager.sendPreparedPayment(prepared)
            }

            transitionTo(.success(paymentHash: nil, feePaid: nil))

        } catch {
            let errorMessage = handleError(error)

            // Check for retryable errors
            if isRetryableError(error) {
                // Retry once automatically
                do {
                    try await withTimeout(seconds: 30) {
                        try await walletManager.sendPreparedPayment(prepared)
                    }
                    transitionTo(.success(paymentHash: nil, feePaid: nil))
                } catch {
                    let retryError = handleError(error)
                    transitionTo(.error(retryError))
                }
            } else {
                transitionTo(.error(errorMessage))
            }
        }
    }

    // MARK: - Helpers

    private func transitionTo(_ newState: SendState) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            state = newState
        }
    }

    private func getInputString(_ inputType: InputType) -> String {
        // Return the original input string that was parsed
        return originalInput
    }

    private func handleError(_ error: Error) -> String {
        if let sdkError = error as? SdkError {
            return sdkError.userFriendlyMessage
        }
        if let sendError = error as? SparkSendError {
            return sendError.errorDescription ?? "Unknown error"
        }
        if error is TimeoutError {
            return "Operation timed out. Please check your connection and try again."
        }
        return error.localizedDescription
    }

    private func isRetryableError(_ error: Error) -> Bool {
        if let sdkError = error as? SdkError {
            switch sdkError {
            case .NetworkError:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TimeoutError.timedOut
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Haptics

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    private func triggerNotificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}

// MARK: - Animation Components (used by SparkSendView)

// Pulsing Bolt Icon
private struct PulsingBoltIcon: View {
    @State private var isPulsing = false

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 64))
            .foregroundStyle(OlasTheme.Colors.zapGold)
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// Shaking Error Icon
private struct ShakingErrorIcon: View {
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 64))
            .foregroundStyle(OlasTheme.Colors.heartRed)
            .offset(x: shakeOffset)
            .onAppear {
                withAnimation(.default.repeatCount(3, autoreverses: true)) {
                    shakeOffset = 10
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    shakeOffset = 0
                }
            }
    }
}

// Scanning Line View
private struct ScanningLineView: View {
    @State private var yPosition: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                colors: [
                    OlasTheme.Colors.zapGold.opacity(0),
                    OlasTheme.Colors.zapGold,
                    OlasTheme.Colors.zapGold.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 2)
            .offset(y: yPosition)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) {
                    yPosition = geometry.size.height
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// Scanner Frame View
private struct ScannerFrameView: View {
    var body: some View {
        GeometryReader { geometry in
            let size: CGFloat = min(geometry.size.width, geometry.size.height) * 0.65
            let cornerLength: CGFloat = 30
            let lineWidth: CGFloat = 4

            ZStack {
                // Top-left
                CornerBracket(cornerLength: cornerLength, lineWidth: lineWidth)
                    .position(x: (geometry.size.width - size) / 2, y: (geometry.size.height - size) / 2)

                // Top-right
                CornerBracket(cornerLength: cornerLength, lineWidth: lineWidth)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .position(x: (geometry.size.width + size) / 2, y: (geometry.size.height - size) / 2)

                // Bottom-left
                CornerBracket(cornerLength: cornerLength, lineWidth: lineWidth)
                    .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
                    .position(x: (geometry.size.width - size) / 2, y: (geometry.size.height + size) / 2)

                // Bottom-right
                CornerBracket(cornerLength: cornerLength, lineWidth: lineWidth)
                    .rotation3DEffect(.degrees(180), axis: (x: 1, y: 1, z: 0))
                    .position(x: (geometry.size.width + size) / 2, y: (geometry.size.height + size) / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

// Corner Bracket Shape
private struct CornerBracket: View {
    let cornerLength: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: cornerLength, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: cornerLength))
        }
        .stroke(OlasTheme.Colors.zapGold, lineWidth: lineWidth)
    }
}

// Rotating Bolt Modifier
private struct RotatingBoltModifier: ViewModifier {
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// Pulsing Scale Modifier
private struct PulsingScaleModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    scale = 1.3
                }
            }
    }
}

// Success Bounce Modifier
private struct SuccessBounceModifier: ViewModifier {
    @State private var scale: CGFloat = 0.5

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                    scale = 1.0
                }
            }
    }
}

// MARK: - Errors (used by SparkSendView)

private enum SparkSendError: LocalizedError {
    case invalidAmount
    case insufficientFunds

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Invalid amount"
        case .insufficientFunds:
            return "Insufficient funds"
        }
    }
}

private enum TimeoutError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        return "Operation timed out"
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
