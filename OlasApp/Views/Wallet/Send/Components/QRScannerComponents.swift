import SwiftUI

// MARK: - Scanning Line View

/// Animated scanning line that moves vertically
public struct ScanningLineView: View {
    @State private var yPosition: CGFloat = 0

    public init() {}

    public var body: some View {
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

// MARK: - Scanner Frame View

/// Corner brackets framing the QR scanner area
public struct ScannerFrameView: View {
    public init() {}

    public var body: some View {
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

// MARK: - Corner Bracket

/// Individual corner bracket shape
public struct CornerBracket: View {
    let cornerLength: CGFloat
    let lineWidth: CGFloat

    public init(cornerLength: CGFloat = 30, lineWidth: CGFloat = 4) {
        self.cornerLength = cornerLength
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Path { path in
            path.move(to: CGPoint(x: cornerLength, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: cornerLength))
        }
        .stroke(OlasTheme.Colors.zapGold, lineWidth: lineWidth)
    }
}
