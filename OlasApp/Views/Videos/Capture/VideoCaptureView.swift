import AVFoundation
import NDKSwiftCore
import SwiftUI

public struct VideoCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PublishingState.self) private var publishingState

    let ndk: NDK

    @State private var cameraSession = CameraSession()
    @State private var videoMode: VideoMode = .vine
    @State private var showModeSheet = false
    @State private var showSettingsSheet = false
    @State private var selectedSpeed: RecordingSpeed = .normal
    @State private var navigateToPreview = false
    @State private var mergedVideoURL: URL?

    // Vlogger tools state
    @State private var countdownSeconds: Int = 0
    @State private var selectedCountdown: CountdownOption = .none
    @State private var showFocusIndicator = false
    @State private var focusIndicatorPosition: CGPoint = .zero

    enum CountdownOption: Int, CaseIterable, Identifiable {
        case none = 0
        case three = 3
        case five = 5
        case ten = 10

        var id: Int { rawValue }

        var label: String {
            self == .none ? "Off" : "\(rawValue)s"
        }
    }

    enum VideoMode: String, CaseIterable, Identifiable {
        case vine = "Vine"
        case short = "Short"

        var id: String { rawValue }

        var maxDuration: TimeInterval {
            switch self {
            case .vine: return 6.0
            case .short: return 60.0
            }
        }

        var color: Color {
            switch self {
            case .vine: return Color(hex: "00BF8F")
            case .short: return Color(hex: "667EEA")
            }
        }
    }

    enum RecordingSpeed: Double, CaseIterable, Identifiable {
        case slow = 0.5
        case normal = 1.0
        case fast = 2.0
        case faster = 3.0

        var id: Double { rawValue }

        var label: String {
            switch self {
            case .slow: return "0.5x"
            case .normal: return "1x"
            case .fast: return "2x"
            case .faster: return "3x"
            }
        }
    }

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
                    // Error state when camera unavailable
                    cameraErrorView(error: error)
                } else if !cameraSession.isConfigured {
                    // Loading state
                    ProgressView()
                        .tint(.white)
                } else {
                    // Grid overlay (rule of thirds)
                    if cameraSession.showGrid {
                        gridOverlay
                    }

                    // Focus indicator
                    if showFocusIndicator {
                        focusIndicatorView
                    }

                    // Screen-edge progress
                    screenEdgeProgress

                    // Countdown overlay
                    if countdownSeconds > 0 {
                        countdownOverlay
                    }

                    // UI Overlays
                    VStack(spacing: 0) {
                        header
                        Spacer()

                        // Audio level meter (when recording)
                        if cameraSession.isRecording {
                            audioLevelMeter
                                .padding(.bottom, 12)
                        }

                        clipsBar
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                        toolsRow
                            .padding(.bottom, 20)
                        captureArea
                            .padding(.bottom, 50)
                    }
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
            cameraSession.stopSession()
            cameraSession.stopAudioLevelMonitoring()
        }
        .sheet(isPresented: $showModeSheet) {
            modeSheet
                .presentationDetents([.height(240)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettingsSheet) {
            settingsSheet
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

    // MARK: - Screen Edge Progress

    private var screenEdgeProgress: some View {
        GeometryReader { _ in
            let progress = cameraSession.recordingTime / videoMode.maxDuration

            Rectangle()
                .fill(.clear)
                .overlay {
                    if cameraSession.isRecording || cameraSession.totalRecordedTime > 0 {
                        RoundedRectangle(cornerRadius: 42)
                            .strokeBorder(
                                AngularGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color(hex: "FF2D55"), location: 0),
                                        .init(color: Color(hex: "FF2D55"), location: progress),
                                        .init(color: .clear, location: progress),
                                    ]),
                                    center: .center,
                                    startAngle: .degrees(-90),
                                    endAngle: .degrees(270)
                                ),
                                lineWidth: 4
                            )
                            .animation(.linear(duration: 0.1), value: progress)
                    }
                }
                .allowsHitTesting(false)
        }
        .padding(8)
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

            // Mode badge
            Button {
                showModeSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: videoMode == .vine ? "leaf.fill" : "film")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(videoMode.color)
                    Text("\(videoMode.rawValue) · \(Int(videoMode.maxDuration))s")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(videoMode.color.opacity(0.2))
                        .overlay(
                            Capsule()
                                .strokeBorder(videoMode.color.opacity(0.4), lineWidth: 1)
                        )
                )
            }

            Spacer()

            HStack(spacing: 8) {
                // External mic indicator
                if cameraSession.isExternalMicConnected {
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

                // Settings
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

    // MARK: - Clips Bar

    private var clipsBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Clips")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(formatTime(cameraSession.totalRecordedTime)) / \(formatTime(videoMode.maxDuration))")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                HStack(spacing: 3) {
                    ForEach(cameraSession.clips) { clip in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [videoMode.color, videoMode.color.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: clipWidth(for: clip.duration, in: geometry.size.width))
                    }

                    // Current recording segment
                    if cameraSession.isRecording {
                        let currentDuration = cameraSession.recordingTime - cameraSession.clips.reduce(0) { $0 + $1.duration }
                        RoundedRectangle(cornerRadius: 2)
                            .fill(videoMode.color)
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
    }

    private func clipWidth(for duration: TimeInterval, in totalWidth: CGFloat) -> CGFloat {
        CGFloat(duration / videoMode.maxDuration) * totalWidth
    }

    @State private var pulsingOpacity: Double = 1.0

    // MARK: - Tools Row

    private var toolsRow: some View {
        HStack(spacing: 32) {
            toolButton(
                icon: cameraSession.isFlashOn ? "bolt.fill" : "bolt.slash",
                label: "Flash",
                isActive: cameraSession.isFlashOn
            ) {
                cameraSession.toggleFlash()
            }

            toolButton(
                icon: "arrow.triangle.2.circlepath.camera",
                label: "Flip",
                isActive: false
            ) {
                cameraSession.flipCamera()
            }

            toolButton(
                icon: "timer",
                label: selectedCountdown.label,
                isActive: selectedCountdown != .none
            ) {
                cycleCountdown()
            }
        }
    }

    private func cycleCountdown() {
        switch selectedCountdown {
        case .none: selectedCountdown = .three
        case .three: selectedCountdown = .five
        case .five: selectedCountdown = .ten
        case .ten: selectedCountdown = .none
        }
    }

    private func toolButton(
        icon: String,
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isActive ? videoMode.color : .white.opacity(0.7))
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Capture Area

    private var captureArea: some View {
        HStack(spacing: 60) {
            // Gallery / last clip preview
            Button {
                if !cameraSession.clips.isEmpty {
                    cameraSession.deleteLastClip()
                }
            } label: {
                if cameraSession.clips.isEmpty {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.1))
                        .frame(width: 54, height: 54)
                        .overlay(
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.5))
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(videoMode.color.opacity(0.3))
                        .frame(width: 54, height: 54)
                        .overlay(
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                }
            }

            // Record button
            recordButton

            // Next / check button
            Button {
                Task {
                    await finishRecording()
                }
            } label: {
                if cameraSession.clips.isEmpty {
                    Circle()
                        .fill(.white.opacity(0.1))
                        .frame(width: 54, height: 54)
                } else {
                    Circle()
                        .fill(videoMode.color)
                        .frame(width: 54, height: 54)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        )
                }
            }
            .disabled(cameraSession.clips.isEmpty)
        }
    }

    private var recordButton: some View {
        ZStack {
            // Outer ring
            Circle()
                .strokeBorder(
                    cameraSession.isRecording ? Color(hex: "FF2D55") : .white.opacity(0.3),
                    lineWidth: 5
                )
                .frame(width: 90, height: 90)
                .shadow(
                    color: cameraSession.isRecording ? Color(hex: "FF2D55").opacity(0.5) : .clear,
                    radius: 15
                )

            // Inner button
            Circle()
                .fill(Color(hex: "FF2D55"))
                .frame(
                    width: cameraSession.isRecording ? 36 : 70,
                    height: cameraSession.isRecording ? 36 : 70
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: cameraSession.isRecording ? 10 : 35
                    )
                )
                .animation(.easeInOut(duration: 0.2), value: cameraSession.isRecording)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !cameraSession.isRecording {
                        startRecording()
                    }
                }
                .onEnded { _ in
                    if cameraSession.isRecording {
                        stopRecording()
                    }
                }
        )
        .overlay(alignment: .bottom) {
            if !cameraSession.isRecording && cameraSession.clips.isEmpty {
                Text("Hold to record")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .offset(y: 30)
            }
        }
    }

    // MARK: - Mode Sheet

    private var modeSheet: some View {
        VStack(spacing: 16) {
            ForEach(VideoMode.allCases) { mode in
                Button {
                    videoMode = mode
                    showModeSheet = false
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(mode.color.opacity(0.2))
                                .frame(width: 48, height: 48)
                            Image(systemName: mode == .vine ? "leaf.fill" : "film")
                                .font(.system(size: 20))
                                .foregroundStyle(mode.color)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(mode == .vine ? "6 second looping video" : "Up to 60 seconds")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Spacer()

                        Circle()
                            .strokeBorder(
                                videoMode == mode ? mode.color : .white.opacity(0.2),
                                lineWidth: 2
                            )
                            .frame(width: 24, height: 24)
                            .overlay {
                                if videoMode == mode {
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
                                        videoMode == mode ? mode.color : .clear,
                                        lineWidth: 2
                                    )
                            )
                    )
                }
            }
        }
        .padding(20)
        .background(Color(hex: "1C1C1E"))
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        NavigationStack {
            List {
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
                                        .foregroundStyle(videoMode.color)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Aspect Ratio")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { cameraSession.isMirrorPreview },
                        set: { cameraSession.setMirrorPreview($0) }
                    )) {
                        Label("Mirror Preview", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    }
                    .tint(videoMode.color)
                } header: {
                    Text("Front Camera")
                } footer: {
                    Text("When enabled, the preview mirrors like a selfie. The recorded video is never mirrored.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Beauty Level")
                            Spacer()
                            Text(cameraSession.beautyLevel > 0 ? "\(Int(cameraSession.beautyLevel * 100))%" : "Off")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $cameraSession.beautyLevel, in: 0...1)
                            .tint(videoMode.color)
                    }
                } header: {
                    Text("Beauty Mode")
                } footer: {
                    Text("Smooths skin and softens features.")
                }

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
                        .tint(videoMode.color)
                    }
                } header: {
                    Text("Zoom")
                }

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
                        .tint(videoMode.color)
                    }

                    Toggle(isOn: Binding(
                        get: { cameraSession.isFocusLocked },
                        set: { _ in cameraSession.toggleFocusLock() }
                    )) {
                        Label("Lock Focus & Exposure", systemImage: "lock.fill")
                    }
                    .tint(videoMode.color)
                } header: {
                    Text("Exposure & Focus")
                } footer: {
                    Text("Tap the preview to set focus point. Lock to prevent auto-adjustments.")
                }

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
                                        .foregroundStyle(videoMode.color)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Recording Speed")
                }

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
                                        .foregroundStyle(videoMode.color)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Filter")
                }

                Section {
                    Toggle(isOn: $cameraSession.showGrid) {
                        Label("Rule of Thirds Grid", systemImage: "grid")
                    }
                    .tint(videoMode.color)
                } header: {
                    Text("Composition")
                }

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
                                        .foregroundStyle(videoMode.color)
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSettingsSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Grid Overlay

    private var gridOverlay: some View {
        GeometryReader { geometry in
            let thirdWidth = geometry.size.width / 3
            let thirdHeight = geometry.size.height / 3

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: thirdWidth, y: 0))
                    path.addLine(to: CGPoint(x: thirdWidth, y: geometry.size.height))
                    path.move(to: CGPoint(x: thirdWidth * 2, y: 0))
                    path.addLine(to: CGPoint(x: thirdWidth * 2, y: geometry.size.height))
                }
                .stroke(.white.opacity(0.3), lineWidth: 1)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: thirdHeight))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: thirdHeight))
                    path.move(to: CGPoint(x: 0, y: thirdHeight * 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: thirdHeight * 2))
                }
                .stroke(.white.opacity(0.3), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Focus Indicator

    private var focusIndicatorView: some View {
        Circle()
            .stroke(videoMode.color, lineWidth: 2)
            .frame(width: 80, height: 80)
            .position(focusIndicatorPosition)
            .allowsHitTesting(false)
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Countdown Overlay

    private var countdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            Text("\(countdownSeconds)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 20)
                .contentTransition(.numericText())
        }
        .allowsHitTesting(false)
    }

    // MARK: - Audio Level Meter

    private var audioLevelMeter: some View {
        HStack(spacing: 4) {
            ForEach(0..<10, id: \.self) { index in
                let threshold = Float(index) / 10.0
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index, level: cameraSession.audioLevel))
                    .frame(width: 6, height: 16)
                    .opacity(cameraSession.audioLevel > threshold ? 1.0 : 0.3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }

    private func barColor(for index: Int, level: Float) -> Color {
        if index < 6 {
            return .green
        } else if index < 8 {
            return .yellow
        } else {
            return level > Float(index) / 10.0 ? .red : .red.opacity(0.5)
        }
    }

    // MARK: - Error View

    private func cameraErrorView(error: CameraSession.CameraError) -> some View {
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

            Button {
                dismiss()
            } label: {
                Text("Go Back")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(videoMode.color)
                    )
            }
        }
        .padding(40)
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
        countdownSeconds = selectedCountdown.rawValue

        Task {
            while countdownSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                withAnimation(.spring(response: 0.3)) {
                    countdownSeconds -= 1
                }
            }
            beginActualRecording()
        }
    }

    private func beginActualRecording() {
        cameraSession.startRecording(maxDuration: videoMode.maxDuration)

        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            pulsingOpacity = 0.6
        }
    }

    private func stopRecording() {
        cameraSession.stopRecording()

        withAnimation(.default) {
            pulsingOpacity = 1.0
        }
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

    // MARK: - Helpers

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

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.setPreviewLayer(previewLayer)
    }
}

class CameraPreviewUIView: UIView {
    private var currentPreviewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        currentPreviewLayer?.frame = bounds
    }

    func setPreviewLayer(_ previewLayer: AVCaptureVideoPreviewLayer?) {
        guard previewLayer !== currentPreviewLayer else { return }

        currentPreviewLayer?.removeFromSuperlayer()
        currentPreviewLayer = previewLayer

        if let previewLayer {
            previewLayer.frame = bounds
            previewLayer.videoGravity = .resizeAspectFill
            layer.insertSublayer(previewLayer, at: 0)
        }
    }
}
