import SwiftUI

// MARK: - Parsing View

/// Loading state view during payment validation
public struct PaymentParsingView: View {
    public init() {}

    public var body: some View {
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
}

// MARK: - Preparing View

/// Loading state view during payment preparation
public struct PaymentPreparingView: View {
    public init() {}

    public var body: some View {
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
}

// MARK: - Sending View

/// Loading state view while payment is being sent
public struct PaymentSendingView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // Rotating bolt
                Image(systemName: "bolt.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(OlasTheme.Colors.zapGold)
                    .rotatingBolt()

                // Pulsing circle
                Circle()
                    .stroke(OlasTheme.Colors.zapGold.opacity(0.3), lineWidth: 2)
                    .frame(width: 100, height: 100)
                    .pulsingScale()
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
}

// MARK: - Success View

/// Success state view after payment completes
public struct PaymentSuccessView: View {
    let feePaid: UInt64?
    let onDismiss: () -> Void

    public init(feePaid: UInt64?, onDismiss: @escaping () -> Void) {
        self.feePaid = feePaid
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 32) {
            // Multi-phase bounce animation
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 96))
                .foregroundStyle(OlasTheme.Colors.success)
                .successBounce()

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

            Button(action: onDismiss) {
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
    }
}

// MARK: - Error View

/// Error state view when payment fails
public struct PaymentErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    public init(message: String, onRetry: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.message = message
        self.onRetry = onRetry
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
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

                VStack(spacing: 16) {
                    Button(action: onRetry) {
                        Text("Try Again")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(OlasTheme.Colors.zapGold)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityLabel("Try payment again")

                    Button(action: onCancel) {
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
                    Button("Close", action: onCancel)
                }
            }
        }
    }
}
