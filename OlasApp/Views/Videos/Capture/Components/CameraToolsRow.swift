import SwiftUI

// MARK: - Camera Tools Row

/// Row of tool buttons for flash, flip camera, and countdown timer
public struct CameraToolsRow: View {
    let isFlashOn: Bool
    let selectedCountdown: CountdownOption
    let videoModeColor: Color
    let onFlashToggle: () -> Void
    let onFlipCamera: () -> Void
    let onCountdownCycle: () -> Void

    public init(
        isFlashOn: Bool,
        selectedCountdown: CountdownOption,
        videoModeColor: Color,
        onFlashToggle: @escaping () -> Void,
        onFlipCamera: @escaping () -> Void,
        onCountdownCycle: @escaping () -> Void
    ) {
        self.isFlashOn = isFlashOn
        self.selectedCountdown = selectedCountdown
        self.videoModeColor = videoModeColor
        self.onFlashToggle = onFlashToggle
        self.onFlipCamera = onFlipCamera
        self.onCountdownCycle = onCountdownCycle
    }

    public var body: some View {
        HStack(spacing: 32) {
            CameraToolButton(
                icon: isFlashOn ? "bolt.fill" : "bolt.slash",
                label: "Flash",
                isActive: isFlashOn,
                activeColor: videoModeColor,
                action: onFlashToggle
            )

            CameraToolButton(
                icon: "arrow.triangle.2.circlepath.camera",
                label: "Flip",
                isActive: false,
                activeColor: videoModeColor,
                action: onFlipCamera
            )

            CameraToolButton(
                icon: "timer",
                label: selectedCountdown.label,
                isActive: selectedCountdown != .none,
                activeColor: videoModeColor,
                action: onCountdownCycle
            )
        }
    }
}

// MARK: - Camera Tool Button

/// Individual tool button with icon and label
public struct CameraToolButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void

    public init(
        icon: String,
        label: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.isActive = isActive
        self.activeColor = activeColor
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isActive ? activeColor : .white.opacity(0.7))
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
