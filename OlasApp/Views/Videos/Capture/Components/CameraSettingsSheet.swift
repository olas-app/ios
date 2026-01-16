import SwiftUI

// MARK: - Camera Settings Sheet

/// Full settings sheet for camera configuration
public struct CameraSettingsSheet: View {
    @Binding var isPresented: Bool
    let cameraSession: CameraSession
    @Binding var selectedSpeed: RecordingSpeed
    @Binding var selectedCountdown: CountdownOption
    let videoModeColor: Color

    public init(
        isPresented: Binding<Bool>,
        cameraSession: CameraSession,
        selectedSpeed: Binding<RecordingSpeed>,
        selectedCountdown: Binding<CountdownOption>,
        videoModeColor: Color
    ) {
        _isPresented = isPresented
        self.cameraSession = cameraSession
        _selectedSpeed = selectedSpeed
        _selectedCountdown = selectedCountdown
        self.videoModeColor = videoModeColor
    }

    public var body: some View {
        NavigationStack {
            List {
                aspectRatioSection
                frontCameraSection
                beautyModeSection
                zoomSection
                exposureSection
                recordingSpeedSection
                filterSection
                compositionSection
                countdownSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var aspectRatioSection: some View {
        Section {
            ForEach(CameraSession.AspectRatio.allCases) { ratio in
                Button {
                    cameraSession.aspectRatio = ratio
                } label: {
                    HStack {
                        Text(ratio.rawValue)
                            .foregroundStyle(.white)
                        Spacer()
                        if cameraSession.aspectRatio == ratio {
                            Image(systemName: "checkmark")
                                .foregroundStyle(videoModeColor)
                        }
                    }
                }
            }
        } header: {
            Text("Aspect Ratio")
        }
    }

    private var frontCameraSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { cameraSession.isMirrorPreview },
                set: { cameraSession.setMirrorPreview($0) }
            )) {
                Label("Mirror Preview", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .tint(videoModeColor)
        } header: {
            Text("Front Camera")
        } footer: {
            Text("When enabled, the preview mirrors like a selfie. The recorded video is never mirrored.")
        }
    }

    private var beautyModeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Beauty Level")
                    Spacer()
                    Text(cameraSession.beautyLevel > 0 ? "\(Int(cameraSession.beautyLevel * 100))%" : "Off")
                        .foregroundStyle(.secondary)
                }
                Slider(value: .init(
                    get: { cameraSession.beautyLevel },
                    set: { cameraSession.beautyLevel = $0 }
                ), in: 0...1)
                    .tint(videoModeColor)
            }
        } header: {
            Text("Beauty Mode")
        } footer: {
            Text("Smooths skin and softens features.")
        }
    }

    private var zoomSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Zoom")
                    Spacer()
                    Text(String(format: "%.1fx", cameraSession.zoomFactor))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { cameraSession.zoomFactor },
                        set: { cameraSession.setZoom($0) }
                    ),
                    in: 1.0...cameraSession.maxZoomFactor
                )
                .tint(videoModeColor)
            }
        } header: {
            Text("Zoom")
        }
    }

    private var exposureSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Exposure")
                    Spacer()
                    Text(cameraSession.exposureValue == 0 ? "Auto" : String(format: "%+.1f", cameraSession.exposureValue))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { cameraSession.exposureValue },
                        set: { cameraSession.setExposure($0) }
                    ),
                    in: -2...2
                )
                .tint(videoModeColor)
            }

            Toggle(isOn: Binding(
                get: { cameraSession.isFocusLocked },
                set: { _ in cameraSession.toggleFocusLock() }
            )) {
                Label("Lock Focus & Exposure", systemImage: "lock.fill")
            }
            .tint(videoModeColor)
        } header: {
            Text("Exposure & Focus")
        } footer: {
            Text("Tap the preview to set focus point. Lock to prevent auto-adjustments.")
        }
    }

    private var recordingSpeedSection: some View {
        Section {
            ForEach(RecordingSpeed.allCases) { speed in
                Button {
                    selectedSpeed = speed
                } label: {
                    HStack {
                        Text(speed.label)
                            .foregroundStyle(.white)
                        Spacer()
                        if selectedSpeed == speed {
                            Image(systemName: "checkmark")
                                .foregroundStyle(videoModeColor)
                        }
                    }
                }
            }
        } header: {
            Text("Recording Speed")
        }
    }

    private var filterSection: some View {
        Section {
            ForEach(CameraSession.VideoFilter.allCases) { filter in
                Button {
                    cameraSession.currentFilter = filter
                } label: {
                    HStack {
                        Text(filter.rawValue)
                            .foregroundStyle(.white)
                        Spacer()
                        if cameraSession.currentFilter == filter {
                            Image(systemName: "checkmark")
                                .foregroundStyle(videoModeColor)
                        }
                    }
                }
            }
        } header: {
            Text("Filter")
        }
    }

    private var compositionSection: some View {
        Section {
            Toggle(isOn: .init(
                get: { cameraSession.showGrid },
                set: { cameraSession.showGrid = $0 }
            )) {
                Label("Rule of Thirds Grid", systemImage: "grid")
            }
            .tint(videoModeColor)
        } header: {
            Text("Composition")
        }
    }

    private var countdownSection: some View {
        Section {
            ForEach(CountdownOption.allCases) { option in
                Button {
                    selectedCountdown = option
                } label: {
                    HStack {
                        Text(option.label)
                            .foregroundStyle(.white)
                        Spacer()
                        if selectedCountdown == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(videoModeColor)
                        }
                    }
                }
            }
        } header: {
            Text("Countdown Timer")
        } footer: {
            Text("Countdown before recording starts.")
        }
    }
}
