import SwiftUI

// MARK: - Record Button

/// Animated record button with hold-to-record gesture
public struct RecordButton: View {
    let isRecording: Bool
    let onRecordStart: () -> Void
    let onRecordStop: () -> Void

    public init(
        isRecording: Bool,
        onRecordStart: @escaping () -> Void,
        onRecordStop: @escaping () -> Void
    ) {
        self.isRecording = isRecording
        self.onRecordStart = onRecordStart
        self.onRecordStop = onRecordStop
    }

    public var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .strokeBorder(
                    isRecording ? Color(hex: "FF2D55") : .white.opacity(0.3),
                    lineWidth: 5
                )
                .frame(width: 90, height: 90)
                .shadow(
                    color: isRecording ? Color(hex: "FF2D55").opacity(0.5) : .clear,
                    radius: 15
                )

            // Inner button
            Circle()
                .fill(Color(hex: "FF2D55"))
                .frame(
                    width: isRecording ? 36 : 70,
                    height: isRecording ? 36 : 70
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: isRecording ? 10 : 35
                    )
                )
                .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isRecording {
                        onRecordStart()
                    }
                }
                .onEnded { _ in
                    if isRecording {
                        onRecordStop()
                    }
                }
        )
    }
}

// MARK: - Capture Area

/// Bottom capture area with gallery, record button, and next button
public struct CaptureArea: View {
    let hasClips: Bool
    let isRecording: Bool
    let videoModeColor: Color
    let onDeleteLastClip: () -> Void
    let onRecordStart: () -> Void
    let onRecordStop: () -> Void
    let onFinish: () -> Void

    public init(
        hasClips: Bool,
        isRecording: Bool,
        videoModeColor: Color,
        onDeleteLastClip: @escaping () -> Void,
        onRecordStart: @escaping () -> Void,
        onRecordStop: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.hasClips = hasClips
        self.isRecording = isRecording
        self.videoModeColor = videoModeColor
        self.onDeleteLastClip = onDeleteLastClip
        self.onRecordStart = onRecordStart
        self.onRecordStop = onRecordStop
        self.onFinish = onFinish
    }

    public var body: some View {
        HStack(spacing: 60) {
            // Gallery / undo button
            Button(action: onDeleteLastClip) {
                if hasClips {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(videoModeColor.opacity(0.3))
                        .frame(width: 54, height: 54)
                        .overlay(
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.1))
                        .frame(width: 54, height: 54)
                        .overlay(
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.5))
                        )
                }
            }
            .disabled(!hasClips)

            // Record button
            VStack(spacing: 0) {
                RecordButton(
                    isRecording: isRecording,
                    onRecordStart: onRecordStart,
                    onRecordStop: onRecordStop
                )

                if !isRecording && !hasClips {
                    Text("Hold to record")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 8)
                }
            }

            // Next button
            Button(action: onFinish) {
                if hasClips {
                    Circle()
                        .fill(videoModeColor)
                        .frame(width: 54, height: 54)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        )
                } else {
                    Circle()
                        .fill(.white.opacity(0.1))
                        .frame(width: 54, height: 54)
                }
            }
            .disabled(!hasClips)
        }
    }
}
