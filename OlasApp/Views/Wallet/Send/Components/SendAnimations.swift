import SwiftUI

// MARK: - Pulsing Bolt Icon

/// Animated bolt icon that pulses during validation
public struct PulsingBoltIcon: View {
    @State private var isPulsing = false

    public init() {}

    public var body: some View {
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

// MARK: - Shaking Error Icon

/// Error icon with shake animation
public struct ShakingErrorIcon: View {
    @State private var shakeOffset: CGFloat = 0
    @State private var resetTask: Task<Void, Never>?

    public init() {}

    public var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 64))
            .foregroundStyle(OlasTheme.Colors.heartRed)
            .offset(x: shakeOffset)
            .onAppear {
                withAnimation(.default.repeatCount(3, autoreverses: true)) {
                    shakeOffset = 10
                }
                resetTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                    shakeOffset = 0
                }
            }
            .onDisappear {
                resetTask?.cancel()
            }
    }
}

// MARK: - Rotating Bolt Modifier

/// View modifier that rotates content continuously
public struct RotatingBoltModifier: ViewModifier {
    @State private var rotation: Double = 0

    public init() {}

    public func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Pulsing Scale Modifier

/// View modifier that pulses scale
public struct PulsingScaleModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0

    public init() {}

    public func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    scale = 1.3
                }
            }
    }
}

// MARK: - Success Bounce Modifier

/// View modifier for success checkmark bounce animation
public struct SuccessBounceModifier: ViewModifier {
    @State private var scale: CGFloat = 0.5

    public init() {}

    public func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                    scale = 1.0
                }
            }
    }
}

// MARK: - View Extensions

public extension View {
    func rotatingBolt() -> some View {
        modifier(RotatingBoltModifier())
    }

    func pulsingScale() -> some View {
        modifier(PulsingScaleModifier())
    }

    func successBounce() -> some View {
        modifier(SuccessBounceModifier())
    }
}
