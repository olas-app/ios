import BreezSdkSpark
import SwiftUI

// MARK: - Send State

/// State machine for the send payment flow
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
        case let (.parsed(a), .parsed(b)):
            return type(of: a) == type(of: b)
        case (.confirm, .confirm):
            return true
        case (.success, .success):
            return true
        case let (.error(a), .error(b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Spark Send View

struct SparkSendView: View {
    var walletManager: SparkWalletManager
    @Environment(\.dismiss) private var dismiss

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
                    PaymentParsingView()
                case let .parsed(inputType):
                    parsedView(inputType: inputType)
                case .preparing:
                    PaymentPreparingView()
                case let .confirm(prepared):
                    confirmView(prepared: prepared)
                case .sending:
                    PaymentSendingView()
                case let .success(_, fee):
                    PaymentSuccessView(feePaid: fee) {
                        dismiss()
                    }
                    .onAppear {
                        HapticFeedback.success()
                    }
                case let .error(message):
                    PaymentErrorView(
                        message: message,
                        onRetry: {
                            HapticFeedback.medium()
                            transitionTo(.scanning)
                        },
                        onCancel: { dismiss() }
                    )
                    .onAppear {
                        HapticFeedback.error()
                    }
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
            QRCameraView { code in
                handleScannedCode(code)
            }
            .ignoresSafeArea()

            ScanningLineView()
            ScannerFrameView()

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
                    HapticFeedback.medium()
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
            HapticFeedback.light()
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
                        HapticFeedback.light()
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
                    HapticFeedback.light()
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

    // MARK: - Parsed View

    @ViewBuilder
    private func parsedView(inputType: InputType) -> some View {
        NavigationStack {
            VStack(spacing: 32) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(OlasTheme.Colors.success)
                    .accessibilityLabel("Payment validated successfully")

                VStack(spacing: 16) {
                    switch inputType {
                    case .bolt11Invoice:
                        parsedInvoiceInfo()
                    case .lightningAddress:
                        parsedAddressInfo()
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

                Button {
                    HapticFeedback.heavy()
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
    private func parsedInvoiceInfo() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lightning Invoice")
                .font(.headline)

            Text("Invoice details will be shown after validation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lightning invoice validated")
    }

    @ViewBuilder
    private func parsedAddressInfo() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lightning Address")
                .font(.headline)

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
                        HapticFeedback.light()
                    }
            }
        }
    }

    // MARK: - Confirm View

    private func confirmView(prepared: PrepareSendPaymentResponse) -> some View {
        NavigationStack {
            VStack(spacing: 32) {
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

                Button {
                    HapticFeedback.heavy()
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
    }

    // MARK: - Actions

    private func handleScannedCode(_ code: String) {
        withAnimation(.easeOut(duration: 0.3)) {
            showFlash = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.3)) {
                showFlash = false
            }
        }

        HapticFeedback.success()

        Task {
            await parseInput(code)
        }
    }

    private func parseInput(_ input: String) async {
        transitionTo(.parsing)

        var cleanedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanedInput.lowercased().hasPrefix("lightning:") {
            cleanedInput = String(cleanedInput.dropFirst(10))
        }

        originalInput = cleanedInput

        do {
            let inputType = try await withTimeout(seconds: 10) {
                try await walletManager.parseInput(cleanedInput)
            }

            transitionTo(.parsed(inputType))

        } catch {
            let errorMessage = SendErrorHandler.userFriendlyMessage(for: error)
            transitionTo(.error(errorMessage))
        }
    }

    private func preparePayment(inputType: InputType) async {
        transitionTo(.preparing)

        do {
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

            let prepared = try await withTimeout(seconds: 10) {
                try await walletManager.preparePayment(input: originalInput, amount: amount)
            }

            transitionTo(.confirm(prepared))

        } catch {
            let errorMessage = SendErrorHandler.userFriendlyMessage(for: error)
            transitionTo(.error(errorMessage))
        }
    }

    private func sendPayment(prepared: PrepareSendPaymentResponse) async {
        transitionTo(.sending)

        do {
            try await withTimeout(seconds: 30) {
                try await walletManager.sendPreparedPayment(prepared)
            }

            transitionTo(.success(paymentHash: nil, feePaid: nil))

        } catch {
            let errorMessage = SendErrorHandler.userFriendlyMessage(for: error)

            if SendErrorHandler.isRetryable(error) {
                do {
                    try await withTimeout(seconds: 30) {
                        try await walletManager.sendPreparedPayment(prepared)
                    }
                    transitionTo(.success(paymentHash: nil, feePaid: nil))
                } catch {
                    let retryError = SendErrorHandler.userFriendlyMessage(for: error)
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
}
