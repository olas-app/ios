// AnimatedBalanceView.swift
import SwiftUI

/// Animated counter that shows balance changes with a rolling number effect
struct AnimatedBalanceView: View {
    let balance: Int64
    let fontSize: CGFloat
    let color: Color

    @State private var displayedBalance: Int64 = 0
    @State private var animationTask: Task<Void, Never>?

    init(balance: Int64, fontSize: CGFloat = 48, color: Color = .primary) {
        self.balance = balance
        self.fontSize = fontSize
        self.color = color
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(formattedBalance)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(displayedBalance)))

            Text(" sats")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .onAppear {
            displayedBalance = balance
        }
        .onChange(of: balance) { oldValue, newValue in
            animateToValue(from: oldValue, to: newValue)
        }
    }

    private var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: displayedBalance)) ?? "0"
    }

    private func animateToValue(from: Int64, to: Int64) {
        // Cancel any existing animation
        animationTask?.cancel()

        let difference = abs(to - from)
        let steps = min(Int(difference), 30) // Max 30 steps for smooth animation
        let stepSize = difference / Int64(max(steps, 1))
        let duration: Double = 0.6 // Total animation duration
        let stepDuration = duration / Double(steps)

        animationTask = Task { @MainActor in
            for i in 1...steps {
                if Task.isCancelled { break }

                let progress = Double(i) / Double(steps)
                // Use easeOut curve for more satisfying animation
                let easedProgress = 1 - pow(1 - progress, 3)

                let newValue: Int64
                if to > from {
                    newValue = from + Int64(Double(difference) * easedProgress)
                } else {
                    newValue = from - Int64(Double(difference) * easedProgress)
                }

                withAnimation(.easeOut(duration: stepDuration)) {
                    displayedBalance = newValue
                }

                try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
            }

            // Ensure we end on the exact target value
            withAnimation(.easeOut(duration: 0.1)) {
                displayedBalance = to
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        AnimatedBalanceView(balance: 12345, color: OlasTheme.Colors.accent)
        AnimatedBalanceView(balance: 99999, fontSize: 32, color: .green)
    }
}
