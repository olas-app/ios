import SwiftUI
import BreezSdkSpark
import NDKSwiftCashu

struct UnifiedDepositView: View {
    let walletType: DepositWallet
    @Environment(\.dismiss) private var dismiss

    @State private var amount: String = "0"
    @State private var selectedCurrency: Currency = .usd
    @State private var depositState: DepositState = .idle
    @State private var selectedMint: String?
    @State private var showCursor = true
    @State private var cashuQuote: CashuMintQuote?

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
            Group {
                if case .monitoring = depositState {
                    invoiceDisplayView
                } else if case .completed = depositState {
                    successView
                } else if case .expired = depositState {
                    expiredView
                } else {
                    amountInputView
                }
            }
            .navigationTitle("Deposit")
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
            startCursorBlink()
            setupDefaultMint()
        }
    }

    // MARK: - Amount Input View

    private var amountInputView: some View {
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

            // Mint selection for Cashu
            if case .cashu(let viewModel, _) = walletType, viewModel.configuredMints.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Deposit to")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Mint", selection: $selectedMint) {
                        ForEach(viewModel.configuredMints, id: \.self) { mint in
                            Text(mintDisplayName(mint))
                                .tag(mint as String?)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
            }

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
                    if case .generating = depositState {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    } else {
                        Text("GENERATE DEPOSIT")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .disabled(amount == "0" || depositState == .generating)
                .opacity(amount == "0" || depositState == .generating ? 0.3 : 1.0)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .alert("Error", isPresented: Binding(
            get: {
                if case .error = depositState { return true }
                return false
            },
            set: { if !$0 { depositState = .idle } }
        )) {
            Button("OK", role: .cancel) {
                depositState = .idle
            }
        } message: {
            if case .error(let message) = depositState {
                Text(message)
            }
        }
    }

    // MARK: - Invoice Display View

    private var invoiceDisplayView: some View {
        ScrollView {
            VStack(spacing: 24) {
                if case .monitoring(let invoice, let amount) = depositState {
                    Text("Pay \(amount) sats")
                        .font(.title.bold())
                        .padding(.top, 20)

                    QRCodeView(content: "lightning:\(invoice)", size: 250)
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

                    Button {
                        UIPasteboard.general.string = invoice
                    } label: {
                        Label("Copy Invoice", systemImage: "doc.on.doc")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Waiting for payment...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    Button {
                        depositState = .idle
                        cashuQuote = nil
                    } label: {
                        Text("Cancel")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 16)

                    Spacer()
                }
            }
        }
        .task {
            await startMonitoring()
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Deposit Complete!")
                .font(.title2.bold())

            if case .completed(let amount) = depositState {
                Text("\(amount) sats added to your wallet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Expired View

    private var expiredView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Invoice Expired")
                .font(.title2.bold())

            Text("The payment request has expired. Please try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                depositState = .idle
                cashuQuote = nil
            } label: {
                Text("Try Again")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Helper Methods

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

        switch walletType {
        case .spark(let manager):
            guard let rate = manager.fiatRates.first(where: { $0.coin == selectedCurrency.rawValue }) else {
                return nil
            }
            return SatsConverter.fiatToSats(fiatAmount, btcRate: rate.value)

        case .cashu:
            return Int64(fiatAmount * 100_000_000)
        }
    }

    private func mintDisplayName(_ mintURL: String) -> String {
        if let url = URL(string: mintURL), let host = url.host {
            return host
        }
        return mintURL
    }

    private func setupDefaultMint() {
        if case .cashu(let viewModel, _) = walletType {
            if selectedMint == nil {
                selectedMint = viewModel.configuredMints.first
            }
        }
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
        guard let fiatValue = Double(amount),
              let satsValue = fiatToSats(fiatValue) else {
            depositState = .error("Invalid amount")
            return
        }

        depositState = .generating

        do {
            let invoice: String

            switch walletType {
            case .spark(let manager):
                invoice = try await manager.createInvoice(
                    amountSats: UInt64(satsValue),
                    description: "Deposit of \(selectedCurrency.symbol)\(amount)"
                )

            case .cashu(let viewModel, _):
                guard let mintURL = selectedMint else {
                    depositState = .error("No mint selected")
                    return
                }

                let quote = try await viewModel.requestDeposit(
                    amount: satsValue,
                    mintURL: mintURL
                )
                cashuQuote = quote
                invoice = quote.invoice
            }

            depositState = .monitoring(invoice: invoice, amount: satsValue)

        } catch {
            depositState = .error(error.localizedDescription)
        }
    }

    private func startMonitoring() async {
        guard case .monitoring(_, let amount) = depositState else { return }

        do {
            switch walletType {
            case .spark(let manager):
                for try await state in manager.monitorInvoice(expectedAmount: UInt64(amount)) {
                    depositState = state
                    if case .completed = state {
                        break
                    }
                }

            case .cashu(let viewModel, _):
                guard let quote = cashuQuote else { return }

                for try await status in await viewModel.monitorDeposit(quote: quote) {
                    switch status {
                    case .pending:
                        break
                    case .minted:
                        await viewModel.refreshBalance()
                        await viewModel.refreshTransactions()
                        depositState = .completed(amount: amount)
                    case .expired:
                        depositState = .expired
                    case .cancelled:
                        depositState = .idle
                    }

                    if case .completed = depositState {
                        break
                    }
                }
            }
        } catch {
            depositState = .error(error.localizedDescription)
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
