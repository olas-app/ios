import SwiftUI

// MARK: - Clips Progress Bar

/// Visual progress bar showing recorded clips and current recording segment
public struct ClipsProgressBar<Clip: Identifiable>: View {
    let clips: [Clip]
    let clipDuration: (Clip) -> TimeInterval
    let totalRecordedTime: TimeInterval
    let maxDuration: TimeInterval
    let isRecording: Bool
    let recordingTime: TimeInterval
    let videoModeColor: Color

    @State private var pulsingOpacity: Double = 1.0

    public init(
        clips: [Clip],
        clipDuration: @escaping (Clip) -> TimeInterval,
        totalRecordedTime: TimeInterval,
        maxDuration: TimeInterval,
        isRecording: Bool,
        recordingTime: TimeInterval,
        videoModeColor: Color
    ) {
        self.clips = clips
        self.clipDuration = clipDuration
        self.totalRecordedTime = totalRecordedTime
        self.maxDuration = maxDuration
        self.isRecording = isRecording
        self.recordingTime = recordingTime
        self.videoModeColor = videoModeColor
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Clips")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(formatTime(totalRecordedTime)) / \(formatTime(maxDuration))")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                HStack(spacing: 3) {
                    ForEach(clips) { clip in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [videoModeColor, videoModeColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: clipWidth(for: clipDuration(clip), in: geometry.size.width))
                    }

                    // Current recording segment
                    if isRecording {
                        let currentDuration = recordingTime - clips.reduce(0) { $0 + clipDuration($1) }
                        RoundedRectangle(cornerRadius: 2)
                            .fill(videoModeColor)
                            .frame(width: clipWidth(for: currentDuration, in: geometry.size.width))
                            .opacity(pulsingOpacity)
                    }

                    Spacer(minLength: 0)
                }
            }
            .frame(height: 6)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.1))
            )
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    pulsingOpacity = 0.6
                }
            } else {
                withAnimation(.default) {
                    pulsingOpacity = 1.0
                }
            }
        }
    }

    private func clipWidth(for duration: TimeInterval, in totalWidth: CGFloat) -> CGFloat {
        CGFloat(duration / maxDuration) * totalWidth
    }

    private func formatTime(_ time: TimeInterval) -> String {
        if time < 10 {
            return String(format: "%.1f", time)
        } else {
            let minutes = Int(time) / 60
            let seconds = Int(time) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
