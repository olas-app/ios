import AVFoundation
import NDKSwiftCore
import SwiftUI

// MARK: - Video Capture View

public struct VideoCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PublishingState.self) private var publishingState

    let ndk: NDK

    @State private var cameraSession = CameraSession()
    @State private var videoMode: VideoMode = .vine
    @State private var showModeSheet = false
    @State private var showSettingsSheet = false
    @State private var selectedSpeed: RecordingSpeed = .normal
    @State private var selectedCountdown: CountdownOption = .none
    @State private var navigateToPreview = false
    @State private var mergedVideoURL: URL?

    // Focus state
    @State private var countdownSeconds: Int = 0
    @State private var showFocusIndicator = false
    @State private var focusIndicatorPosition: CGPoint = .zero
    @State private var countdownTask: Task<Void, Never>?

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview with focus tap gesture
                CameraPreviewView(previewLayer: cameraSession.previewLayer)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { event in
                                handleFocusTap(at: event.location, in: geometry.size)
                            }
                    )

                if let error = cameraSession.error {
                    CameraErrorView(
                        error: error,
                        videoModeColor: videoMode.color,
                        onDismiss: { dismiss() }
                    )
                } else if !cameraSession.isConfigured {
                    ProgressView()
                        .tint(.white)
                } else {
                    cameraOverlays
                    controlsOverlay
                }
            }
        }
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if cameraSession.error != nil {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await cameraSession.setupSession()
            cameraSession.startSession()
            cameraSession.startAudioLevelMonitoring()
        }
        .onDisappear {
            countdownTask?.cancel()
            cameraSession.stopSession()
            cameraSession.stopAudioLevelMonitoring()
        }
        .sheet(isPresented: $showModeSheet) {
            VideoModeSheet(selectedMode: $videoMode, isPresented: $showModeSheet)
                .presentationDetents([.height(240)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettingsSheet) {
            CameraSettingsSheet(
                isPresented: $showSettingsSheet,
                cameraSession: cameraSession,
                selectedSpeed: $selectedSpeed,
                selectedCountdown: $selectedCountdown,
                videoModeColor: videoMode.color
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $navigateToPreview) {
            if let url = mergedVideoURL {
                VideoPreviewView(
                    videoURL: url,
                    videoMode: videoMode,
                    ndk: ndk
                )
            }
        }
    }

    // MARK: - Camera Overlays

    @ViewBuilder
    private var cameraOverlays: some View {
        // Grid overlay (rule of thirds)
        if cameraSession.showGrid {
            GridOverlay()
        }

        // Focus indicator
        FocusIndicator(
            position: focusIndicatorPosition,
            isVisible: showFocusIndicator,
            color: videoMode.color
        )

        // Screen-edge progress
        ScreenEdgeProgress(
            progress: cameraSession.recordingTime / videoMode.maxDuration,
            isVisible: cameraSession.isRecording || cameraSession.totalRecordedTime > 0
        )

        // Countdown overlay
        if countdownSeconds > 0 {
            CountdownOverlay(seconds: countdownSeconds)
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            header
            Spacer()

            // Audio level meter (when recording)
            if cameraSession.isRecording {
                AudioLevelMeter(audioLevel: cameraSession.audioLevel)
                    .padding(.bottom, 12)
            }

            ClipsProgressBar(
                clips: cameraSession.clips,
                clipDuration: { $0.duration },
                totalRecordedTime: cameraSession.totalRecordedTime,
                maxDuration: videoMode.maxDuration,
                isRecording: cameraSession.isRecording,
                recordingTime: cameraSession.recordingTime,
                videoModeColor: videoMode.color
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            CameraToolsRow(
                isFlashOn: cameraSession.isFlashOn,
                selectedCountdown: selectedCountdown,
                videoModeColor: videoMode.color,
                onFlashToggle: { cameraSession.toggleFlash() },
                onFlipCamera: { cameraSession.flipCamera() },
                onCountdownCycle: { selectedCountdown = selectedCountdown.next }
            )
            .padding(.bottom, 20)

            CaptureArea(
                hasClips: !cameraSession.clips.isEmpty,
                isRecording: cameraSession.isRecording,
                videoModeColor: videoMode.color,
                onDeleteLastClip: { cameraSession.deleteLastClip() },
                onRecordStart: startRecording,
                onRecordStop: stopRecording,
                onFinish: { Task { await finishRecording() } }
            )
            .padding(.bottom, 50)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                if cameraSession.clips.isEmpty {
                    dismiss()
                } else {
                    cameraSession.deleteAllClips()
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            ModeBadge(mode: videoMode) {
                showModeSheet = true
            }

            Spacer()

            HStack(spacing: 8) {
                if cameraSession.isExternalMicConnected {
                    ExternalMicIndicator()
                }

                Button {
                    showSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 60)
    }

    // MARK: - Actions

    private func handleFocusTap(at location: CGPoint, in size: CGSize) {
        guard cameraSession.isConfigured, !cameraSession.isRecording else { return }

        focusIndicatorPosition = location
        withAnimation(.easeOut(duration: 0.15)) {
            showFocusIndicator = true
        }

        let normalizedPoint = CGPoint(
            x: location.x / size.width,
            y: location.y / size.height
        )
        cameraSession.setFocus(at: normalizedPoint)

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) {
                showFocusIndicator = false
            }
        }
    }

    private func startRecording() {
        guard cameraSession.totalRecordedTime < videoMode.maxDuration else { return }

        if selectedCountdown != .none {
            startCountdown()
        } else {
            beginActualRecording()
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownSeconds = selectedCountdown.rawValue

        countdownTask = Task { @MainActor in
            while countdownSeconds > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.3)) {
                    countdownSeconds -= 1
                }
            }
            guard !Task.isCancelled else { return }
            beginActualRecording()
        }
    }

    private func beginActualRecording() {
        cameraSession.startRecording(maxDuration: videoMode.maxDuration)
    }

    private func stopRecording() {
        cameraSession.stopRecording()
    }

    private func finishRecording() async {
        do {
            let url = try await cameraSession.mergeClips()
            await MainActor.run {
                mergedVideoURL = url
                navigateToPreview = true
            }
        } catch {
            // Handle error
        }
    }
}
