import UIKit

// MARK: - Haptic Feedback

/// Centralized haptic feedback utilities
public enum HapticFeedback {
    /// Triggers an impact haptic with the specified style
    public static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    /// Triggers a notification haptic with the specified type
    public static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    /// Convenience methods for common haptics
    public static func light() {
        impact(.light)
    }

    public static func medium() {
        impact(.medium)
    }

    public static func heavy() {
        impact(.heavy)
    }

    public static func success() {
        notification(.success)
    }

    public static func warning() {
        notification(.warning)
    }

    public static func error() {
        notification(.error)
    }
}
