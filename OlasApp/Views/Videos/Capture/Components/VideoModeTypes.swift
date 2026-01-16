import SwiftUI

// MARK: - Video Mode

/// Defines the video recording mode with duration limits and visual styling
public enum VideoMode: String, CaseIterable, Identifiable {
    case vine = "Vine"
    case short = "Short"

    public var id: String { rawValue }

    public var maxDuration: TimeInterval {
        switch self {
        case .vine: return 6.0
        case .short: return 60.0
        }
    }

    public var color: Color {
        switch self {
        case .vine: return Color(hex: "00BF8F")
        case .short: return Color(hex: "667EEA")
        }
    }

    public var description: String {
        switch self {
        case .vine: return "6 second looping video"
        case .short: return "Up to 60 seconds"
        }
    }

    public var icon: String {
        switch self {
        case .vine: return "leaf.fill"
        case .short: return "film"
        }
    }
}

// MARK: - Recording Speed

/// Playback speed multiplier for recording
public enum RecordingSpeed: Double, CaseIterable, Identifiable {
    case slow = 0.5
    case normal = 1.0
    case fast = 2.0
    case faster = 3.0

    public var id: Double { rawValue }

    public var label: String {
        switch self {
        case .slow: return "0.5x"
        case .normal: return "1x"
        case .fast: return "2x"
        case .faster: return "3x"
        }
    }
}

// MARK: - Countdown Option

/// Countdown timer options before recording starts
public enum CountdownOption: Int, CaseIterable, Identifiable {
    case none = 0
    case three = 3
    case five = 5
    case ten = 10

    public var id: Int { rawValue }

    public var label: String {
        self == .none ? "Off" : "\(rawValue)s"
    }

    public var next: CountdownOption {
        switch self {
        case .none: return .three
        case .three: return .five
        case .five: return .ten
        case .ten: return .none
        }
    }
}
