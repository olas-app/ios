import SwiftUI

// MARK: - Video Mode Sheet

/// Bottom sheet for selecting video recording mode (Vine/Short)
public struct VideoModeSheet: View {
    @Binding var selectedMode: VideoMode
    @Binding var isPresented: Bool

    public init(selectedMode: Binding<VideoMode>, isPresented: Binding<Bool>) {
        _selectedMode = selectedMode
        _isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 16) {
            ForEach(VideoMode.allCases) { mode in
                VideoModeOption(
                    mode: mode,
                    isSelected: selectedMode == mode
                ) {
                    selectedMode = mode
                    isPresented = false
                }
            }
        }
        .padding(20)
        .background(Color(hex: "1C1C1E"))
    }
}

// MARK: - Video Mode Option

/// Individual mode option row in the mode selection sheet
public struct VideoModeOption: View {
    let mode: VideoMode
    let isSelected: Bool
    let onSelect: () -> Void

    public init(mode: VideoMode, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.mode = mode
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(mode.color.opacity(0.2))
                        .frame(width: 48, height: 48)
                    Image(systemName: mode.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(mode.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(mode.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Circle()
                    .strokeBorder(
                        isSelected ? mode.color : .white.opacity(0.2),
                        lineWidth: 2
                    )
                    .frame(width: 24, height: 24)
                    .overlay {
                        if isSelected {
                            Circle()
                                .fill(mode.color)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                        }
                    }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? mode.color : .clear,
                                lineWidth: 2
                            )
                    )
            )
        }
    }
}

// MARK: - Mode Badge

/// Compact mode badge shown in the header
public struct ModeBadge: View {
    let mode: VideoMode
    let onTap: () -> Void

    public init(mode: VideoMode, onTap: @escaping () -> Void) {
        self.mode = mode
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(mode.color)
                Text("\(mode.rawValue) \u{00B7} \(Int(mode.maxDuration))s")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(mode.color.opacity(0.2))
                    .overlay(
                        Capsule()
                            .strokeBorder(mode.color.opacity(0.4), lineWidth: 1)
                    )
            )
        }
    }
}
