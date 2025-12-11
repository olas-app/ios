import SwiftUI
import BreezSdkSpark

struct ModernReceiveView: View {
    var walletManager: SparkWalletManager
    @Environment(\.dismiss) private var dismiss

    @State private var amount: String = "0"
    @State private var selectedCurrency: Currency = .usd
    @State private var isGenerating = false
    @State private var error: String?
    @State private var generatedInvoice: String?
    @State private var showInvoiceSheet = false
    @State private var showCursor = true

    enum Currency: String, CaseIterable {
        case sat = "SAT"
        case usd = "USD"
        case eur = "EUR"
        case gbp = "GBP"
        case jpy = "JPY"

        var symbol: String {
            switch self {
            case .sat: return ""
            case .usd: return "$"
            case .eur: return "€"
            case .gbp: return "£"
            case .jpy: return "¥"
            }
        }

        var quickAmounts: [Int] {
            switch self {
            case .sat: return [1000, 5000, 10000, 21000, 50000, 100000]
            case .usd: return [1, 5, 10, 20, 50, 100]
            case .eur: return [1, 5, 10, 20, 50, 100]
            case .gbp: return [1, 5, 10, 20, 50, 100]
            case .jpy: return [100, 500, 1000, 2000, 5000, 10000]
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Amount section
                VStack(spacing: 32) {
                    // Currency selector
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Currency.allCases, id: \.self) { currency in
                                Button {
                                    selectedCurrency = currency
                                } label: {
                                    Text(currency.rawValue)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(selectedCurrency == currency ? .white : .primary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(selectedCurrency == currency ? Color.accentColor : Color(.systemGray5))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Amount display
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(selectedCurrency.symbol)
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 0) {
                            Text(amount)
                                .font(.system(size: 96, weight: .light))
                                .foregroundStyle(amount == "0" ? .secondary : .primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)

                            if showCursor {
                                Rectangle()
                                    .fill(.primary)
                                    .frame(width: 3, height: 80)
                                    .padding(.leading, 4)
                            }
                        }
                    }
                    .frame(height: 96)

                    // Sats equivalent
                    Text(satsEquivalent)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                // Keypad section
                VStack(spacing: 24) {
                    // Quick amounts
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedCurrency.quickAmounts, id: \.self) { quickAmount in
                                Button {
                                    amount = "\(quickAmount)"
                                } label: {
                                    Text(selectedCurrency.symbol + "\(quickAmount)")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 10)
                                        .background(Color(.systemGray6))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 20)

                    // Keypad
                    VStack(spacing: 20) {
                        HStack(spacing: 20) {
                            KeypadButton(digit: "1") { addDigit("1") }
                            KeypadButton(digit: "2") { addDigit("2") }
                            KeypadButton(digit: "3") { addDigit("3") }
                        }
                        HStack(spacing: 20) {
                            KeypadButton(digit: "4") { addDigit("4") }
                            KeypadButton(digit: "5") { addDigit("5") }
                            KeypadButton(digit: "6") { addDigit("6") }
                        }
                        HStack(spacing: 20) {
                            KeypadButton(digit: "7") { addDigit("7") }
                            KeypadButton(digit: "8") { addDigit("8") }
                            KeypadButton(digit: "9") { addDigit("9") }
                        }
                        HStack(spacing: 20) {
                            KeypadButton(digit: ".") { addDecimal() }
                            KeypadButton(digit: "0") { addDigit("0") }
                            KeypadButton(digit: "⌫", isBackspace: true) { backspace() }
                        }
                    }
                    .padding(.horizontal, 40)

                    // Generate button
                    Button {
                        Task {
                            await generateInvoice()
                        }
                    } label: {
                        Text("REQUEST PAYMENT")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(amount == "0" || isGenerating)
                    .opacity(amount == "0" ? 0.3 : 1.0)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Receive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showInvoiceSheet) {
                if let invoice = generatedInvoice {
                    InvoiceDisplayView(invoice: invoice) {
                        generatedInvoice = nil
                        showInvoiceSheet = false
                    }
                }
            }
            .onChange(of: generatedInvoice) { _, newValue in
                showInvoiceSheet = newValue != nil
            }
            .alert("Error", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) {
                    error = nil
                }
            } message: {
                if let errorMessage = error {
                    Text(errorMessage)
                }
            }
        }
        .onAppear {
            startCursorBlink()
        }
    }

    private var satsEquivalent: String {
        if selectedCurrency == .sat {
            return "Satoshis"
        }

        guard let fiatValue = Double(amount),
              let sats = fiatToSats(fiatValue) else {
            return "0 sats"
        }

        return "\(sats.formatted()) sats"
    }

    private func fiatToSats(_ fiatAmount: Double) -> Int64? {
        guard selectedCurrency != .sat else {
            return Int64(fiatAmount)
        }

        guard let rate = walletManager.fiatRates.first(where: { $0.coin == selectedCurrency.rawValue }) else {
            return nil
        }

        return SatsConverter.fiatToSats(fiatAmount, btcRate: rate.value)
    }

    private func addDigit(_ digit: String) {
        if amount == "0" {
            amount = digit
        } else if amount.count < 10 {
            amount += digit
        }
    }

    private func addDecimal() {
        if !amount.contains(".") && amount.count < 10 {
            amount += "."
        }
    }

    private func backspace() {
        if amount.count == 1 {
            amount = "0"
        } else {
            amount = String(amount.dropLast())
        }
    }

    private func startCursorBlink() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            showCursor.toggle()
        }
    }

    private func generateInvoice() async {
        isGenerating = true
        defer { isGenerating = false }

        guard let fiatValue = Double(amount) else {
            error = "Invalid amount"
            return
        }

        guard let satsValue = fiatToSats(fiatValue) else {
            error = "Unable to fetch exchange rate. Please try again."
            return
        }

        let sats = UInt64(satsValue)

        do {
            let invoice = try await walletManager.createInvoice(
                amountSats: sats,
                description: "Payment of \(selectedCurrency.symbol)\(amount)"
            )
            generatedInvoice = invoice
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Keypad Button

private struct KeypadButton: View {
    let digit: String
    let isBackspace: Bool
    let action: () -> Void

    init(digit: String, isBackspace: Bool = false, action: @escaping () -> Void) {
        self.digit = digit
        self.isBackspace = isBackspace
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(digit)
                .font(.system(size: isBackspace ? 28 : (digit == "." ? 48 : 36), weight: .light))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(KeypadButtonStyle())
    }
}

private struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color(.systemGray4) : .clear)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Invoice Display

struct InvoiceDisplayView: View {
    let invoice: String
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Lightning Invoice")
                        .font(.title2.bold())
                        .padding(.top, 20)

                    QRCodeView(content: invoice, size: 250)
                        .padding()

                    Text(invoice)
                        .font(.caption.monospaced())
                        .lineLimit(4)
                        .truncationMode(.middle)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)

                    HStack(spacing: 16) {
                        Button {
                            UIPasteboard.general.string = invoice
                            copied = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                copied = false
                            }
                        } label: {
                            HStack {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                Text(copied ? "Copied!" : "Copy Invoice")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        }

                        ShareLink(item: invoice) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundStyle(.primary)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)

                    Text("Scan this QR code or share the invoice to receive payment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationTitle("Receive Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}
