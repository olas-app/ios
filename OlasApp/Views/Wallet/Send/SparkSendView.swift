import BreezSdkSpark
import SwiftUI

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
                case let .parsed(inputType):
                    parsedView(inputType: inputType)
                case .preparing:
                    preparingView
                case let .confirm(prepared):
                    confirmView(prepared: prepared)
                case .sending:
                    sendingView
                case let .success(hash, fee):
                    successView(paymentHash: hash, feePaid: fee)
                case let .error(message):
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
                    case let .bolt11Invoice(invoice):
                        parsedInvoiceInfo(invoice)
                    case let .lightningAddress(address):
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
    private func parsedInvoiceInfo(_: some Any) -> some View {
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
    private func parsedAddressInfo(_: some Any) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lightning Address")
                .font(.headline)

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

    private func successView(paymentHash _: String?, feePaid: UInt64?) -> some View {
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

    private func getInputString(_: InputType) -> String {
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
                    OlasTheme.Colors.zapGold.opacity(0),
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
