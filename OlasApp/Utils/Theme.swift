// Theme.swift
import SwiftUI

public enum OlasTheme {
    // MARK: - Colors

    // Use iOS system colors for backgrounds (Color(.systemBackground), Color(.systemGray5), etc.)
    // These accent colors are for highlights, feedback, and branding only
    public enum Colors {
        // Primary accent - almost black, neutral
        public static let accent = Color(hex: "1A1A1A")

        // Wave gradient colors (for special branding moments)
        public static let waveBlue = Color(hex: "2563EB")
        public static let waveCyan = Color(hex: "06B6D4")
        public static let waveGradient = LinearGradient(
            colors: [waveBlue, waveCyan],
            startPoint: .leading,
            endPoint: .trailing
        )

        // Feedback colors
        public static let zapGold = Color(hex: "FFB800")
        public static let heartRed = Color(hex: "FF4757")
        public static let repostGreen = Color(hex: "00C853")
        public static let success = Color(hex: "2ED573")
    }

    // MARK: - Glassmorphism

    public enum Glass {
        // MARK: - Corner Radius
        public static let cornerRadius: CGFloat = 20

        // MARK: - Shadow Parameters
        public enum Shadow {
            public static let radius: CGFloat = 20
            public static let opacity: Double = 0.1
            public static let yOffset: CGFloat = 10
        }

        // MARK: - Defaults
        public enum Defaults {
            public static let level: Level = .ultraThin
            public static let cornerRadius: CGFloat = Glass.cornerRadius
        }

        // MARK: - Glass Levels
        /// Glass intensity levels mapped to SwiftUI materials.
        /// - `ultraThin`: Maps to `.ultraThinMaterial` - most transparent
        /// - `thin`: Maps to `.thinMaterial` - moderate transparency
        /// - `regular`: Maps to `.regularMaterial` - least transparent
        public enum Level {
            case ultraThin
            case thin
            case regular

            public var material: Material {
                switch self {
                case .ultraThin:
                    return .ultraThinMaterial
                case .thin:
                    return .thinMaterial
                case .regular:
                    return .regularMaterial
                }
            }

            public var shadowOpacity: Double {
                switch self {
                case .ultraThin:
                    return Shadow.opacity * 0.5
                case .thin:
                    return Shadow.opacity
                case .regular:
                    return Shadow.opacity * 1.5
                }
            }
        }

        // Legacy support
        @available(*, deprecated, renamed: "OlasTheme.Glass.Shadow.radius")
        public static let shadowRadius: CGFloat = Shadow.radius
        @available(*, deprecated, renamed: "OlasTheme.Glass.Shadow.opacity")
        public static let shadowOpacity: Double = Shadow.opacity
    }

    // MARK: - Spacing

    public enum Spacing {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 24
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

public struct GlassBackground: ViewModifier {
    let level: OlasTheme.Glass.Level
    let cornerRadius: CGFloat

    public init(
        level: OlasTheme.Glass.Level = OlasTheme.Glass.Defaults.level,
        cornerRadius: CGFloat = OlasTheme.Glass.Defaults.cornerRadius
    ) {
        self.level = level
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(level.material)
            .cornerRadius(cornerRadius)
            .shadow(
                color: .black.opacity(level.shadowOpacity),
                radius: OlasTheme.Glass.Shadow.radius,
                y: OlasTheme.Glass.Shadow.yOffset
            )
    }
}

public extension View {
    /// Applies a glass background with the specified level and corner radius
    /// - Parameters:
    ///   - level: The glass intensity level (ultraThin, thin, regular). Defaults to `.ultraThin`
    ///   - cornerRadius: The corner radius. Defaults to `OlasTheme.Glass.cornerRadius` (20pt)
    func glassBackground(
        level: OlasTheme.Glass.Level = OlasTheme.Glass.Defaults.level,
        cornerRadius: CGFloat = OlasTheme.Glass.Defaults.cornerRadius
    ) -> some View {
        modifier(GlassBackground(level: level, cornerRadius: cornerRadius))
    }
}
