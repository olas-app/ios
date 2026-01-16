import SwiftUI

// MARK: - Camera Error View

/// Error display when camera is unavailable
public struct CameraErrorView: View {
    let error: CameraSession.CameraError
    let videoModeColor: Color
    let onDismiss: () -> Void

    public init(
        error: CameraSession.CameraError,
        videoModeColor: Color,
        onDismiss: @escaping () -> Void
    ) {
        self.error = error
        self.videoModeColor = videoModeColor
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.5))

            VStack(spacing: 8) {
                Text("Camera Unavailable")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                Text(error.localizedDescription)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                #if targetEnvironment(simulator)
                Text("Camera is not supported in the Simulator. Please test on a physical device.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                #endif
            }

            Button(action: onDismiss) {
                Text("Go Back")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(videoModeColor)
                    )
            }
        }
        .padding(40)
    }
}

// MARK: - External Mic Indicator

/// Badge showing external microphone is connected
public struct ExternalMicIndicator: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12))
            Text("EXT")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.green.opacity(0.2))
        )
    }
}
