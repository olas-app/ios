import SwiftUI

// MARK: - Screen Edge Progress

/// Circular progress indicator around the screen edge during recording
public struct ScreenEdgeProgress: View {
    let progress: Double
    let isVisible: Bool

    public init(progress: Double, isVisible: Bool) {
        self.progress = progress
        self.isVisible = isVisible
    }

    public var body: some View {
        GeometryReader { _ in
            Rectangle()
                .fill(.clear)
                .overlay {
                    if isVisible {
                        RoundedRectangle(cornerRadius: 42)
                            .strokeBorder(
                                AngularGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color(hex: "FF2D55"), location: 0),
                                        .init(color: Color(hex: "FF2D55"), location: progress),
                                        .init(color: .clear, location: progress),
                                    ]),
                                    center: .center,
                                    startAngle: .degrees(-90),
                                    endAngle: .degrees(270)
                                ),
                                lineWidth: 4
                            )
                            .animation(.linear(duration: 0.1), value: progress)
                    }
                }
                .allowsHitTesting(false)
        }
        .padding(8)
    }
}

// MARK: - Grid Overlay

/// Rule of thirds grid overlay for composition
public struct GridOverlay: View {
    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let thirdWidth = geometry.size.width / 3
            let thirdHeight = geometry.size.height / 3

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: thirdWidth, y: 0))
                    path.addLine(to: CGPoint(x: thirdWidth, y: geometry.size.height))
                    path.move(to: CGPoint(x: thirdWidth * 2, y: 0))
                    path.addLine(to: CGPoint(x: thirdWidth * 2, y: geometry.size.height))
                }
                .stroke(.white.opacity(0.3), lineWidth: 1)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: thirdHeight))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: thirdHeight))
                    path.move(to: CGPoint(x: 0, y: thirdHeight * 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: thirdHeight * 2))
                }
                .stroke(.white.opacity(0.3), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Focus Indicator

/// Animated focus indicator shown when tapping to focus
public struct FocusIndicator: View {
    let position: CGPoint
    let isVisible: Bool
    let color: Color

    public init(position: CGPoint, isVisible: Bool, color: Color) {
        self.position = position
        self.isVisible = isVisible
        self.color = color
    }

    public var body: some View {
        if isVisible {
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 80, height: 80)
                .position(position)
                .allowsHitTesting(false)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Countdown Overlay

/// Full-screen countdown overlay before recording starts
public struct CountdownOverlay: View {
    let seconds: Int

    public init(seconds: Int) {
        self.seconds = seconds
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            Text("\(seconds)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 20)
                .contentTransition(.numericText())
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Audio Level Meter

/// Visual audio level meter showing microphone input levels
public struct AudioLevelMeter: View {
    let audioLevel: Float
    let barCount: Int

    public init(audioLevel: Float, barCount: Int = 10) {
        self.audioLevel = audioLevel
        self.barCount = barCount
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                let threshold = Float(index) / Float(barCount)
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 6, height: 16)
                    .opacity(audioLevel > threshold ? 1.0 : 0.3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }

    private func barColor(for index: Int) -> Color {
        if index < 6 {
            return .green
        } else if index < 8 {
            return .yellow
        } else {
            return audioLevel > Float(index) / Float(barCount) ? .red : .red.opacity(0.5)
        }
    }
}
