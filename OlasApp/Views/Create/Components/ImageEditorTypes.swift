import SwiftUI

// MARK: - Image Filter

/// Available image filters for photo editing
public enum ImageFilter: String, CaseIterable, Identifiable {
    case original = "Original"
    case clarendon = "Clarendon"
    case gingham = "Gingham"
    case moon = "Moon"
    case lark = "Lark"
    case reyes = "Reyes"
    case juno = "Juno"
    case slumber = "Slumber"
    case crema = "Crema"
    case ludwig = "Ludwig"
    case aden = "Aden"
    case perpetua = "Perpetua"

    public var id: String { rawValue }
}

// MARK: - Image Adjustment

/// Available image adjustments with their ranges and defaults
public enum ImageAdjustment: String, CaseIterable, Identifiable {
    case brightness = "Brightness"
    case contrast = "Contrast"
    case saturation = "Saturation"
    case warmth = "Warmth"
    case shadows = "Shadows"
    case highlights = "Highlights"
    case vignette = "Vignette"
    case sharpen = "Sharpen"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .brightness: return "sun.max"
        case .contrast: return "circle.righthalf.filled"
        case .saturation: return "drop.fill"
        case .warmth: return "thermometer.medium"
        case .shadows: return "square.lefthalf.filled"
        case .highlights: return "bolt.fill"
        case .vignette: return "camera.aperture"
        case .sharpen: return "triangle"
        }
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .brightness: return -1.0 ... 1.0
        case .contrast: return 0.5 ... 2.0
        case .saturation: return 0.0 ... 2.0
        case .warmth: return -1.0 ... 1.0
        case .shadows: return -1.0 ... 1.0
        case .highlights: return -1.0 ... 1.0
        case .vignette: return 0.0 ... 2.0
        case .sharpen: return 0.0 ... 2.0
        }
    }

    public var defaultValue: Double {
        switch self {
        case .brightness: return 0.0
        case .contrast: return 1.0
        case .saturation: return 1.0
        case .warmth: return 0.0
        case .shadows: return 0.0
        case .highlights: return 0.0
        case .vignette: return 0.0
        case .sharpen: return 0.0
        }
    }

    /// Formats the adjustment value for display
    public func formatValue(_ value: Double) -> String {
        switch self {
        case .brightness, .warmth, .shadows, .highlights:
            return String(format: "%+.0f", value * 100)
        case .contrast, .saturation:
            return String(format: "%.0f", (value - 1) * 100)
        case .vignette, .sharpen:
            return String(format: "%.0f", value * 50)
        }
    }
}

// MARK: - Aspect Ratio

/// Available aspect ratios for image cropping
public enum ImageAspectRatio: String, CaseIterable, Identifiable {
    case square = "1:1"
    case portrait = "4:5"
    case landscape = "16:9"
    case free = "Free"

    public var id: String { rawValue }

    public var ratio: CGFloat? {
        switch self {
        case .square: return 1.0
        case .portrait: return 4.0 / 5.0
        case .landscape: return 16.0 / 9.0
        case .free: return nil
        }
    }
}

// MARK: - Editor Panel

/// Available panels in the image editor
public enum EditorPanel: String, CaseIterable {
    case crop = "Crop"
    case filters = "Filters"
    case adjust = "Adjust"

    public var icon: String {
        switch self {
        case .crop: return "crop"
        case .filters: return "camera.filters"
        case .adjust: return "slider.horizontal.3"
        }
    }
}
