import AVFoundation
import CoreImage
import SwiftUI

@MainActor
@Observable
final class CameraSession: NSObject {
    // MARK: - Published State

    var isSessionRunning = false
    var isRecording = false
    var recordingTime: TimeInterval = 0
    var currentFilter: VideoFilter = .none
    var isFlashOn = false
    var isFrontCamera = false
    var zoomFactor: CGFloat = 1.0
    var maxZoomFactor: CGFloat = 5.0

    // Vlogger tools
    var exposureValue: Float = 0.0 // -2 to +2 EV
    var isFocusLocked = false
    var focusPoint: CGPoint?
    var audioLevel: Float = 0.0 // 0 to 1
    var isExternalMicConnected = false
    var isMirrorPreview = true // For front camera
    var showGrid = false
    var beautyLevel: Float = 0.0 // 0 to 1
    var aspectRatio: AspectRatio = .portrait

    // Recorded clips
    var clips: [RecordedClip] = []
    var totalRecordedTime: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }

    // Errors
    var error: CameraError?

    // Configuration state
    private(set) var isConfigured = false

    // Preview layer
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Private

    private let captureSession = AVCaptureSession()
    private var videoOutput: AVCaptureMovieFileOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var currentVideoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private var recordingTimer: Timer?
    private var audioLevelTimer: Timer?
    private var currentClipStartTime: TimeInterval = 0
    private var tempVideoURL: URL?

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let audioQueue = DispatchQueue(label: "camera.audio.queue")

    // MARK: - Types

    struct RecordedClip: Identifiable {
        let id = UUID()
        let url: URL
        let duration: TimeInterval
    }

    enum CameraError: LocalizedError {
        case cameraUnavailable
        case microphoneUnavailable
        case configurationFailed
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable: return "Camera is unavailable"
            case .microphoneUnavailable: return "Microphone is unavailable"
            case .configurationFailed: return "Failed to configure camera"
            case .recordingFailed: return "Recording failed"
            }
        }
    }

    enum VideoFilter: String, CaseIterable, Identifiable {
        case none = "Original"
        case noir = "Noir"
        case vivid = "Vivid"
        case warm = "Warm"
        case cool = "Cool"
        case fade = "Fade"

        var id: String { rawValue }

        var ciFilterName: String? {
            switch self {
            case .none: return nil
            case .noir: return "CIPhotoEffectNoir"
            case .vivid: return "CIColorControls" // saturation boost
            case .warm: return "CITemperatureAndTint"
            case .cool: return "CITemperatureAndTint"
            case .fade: return "CIPhotoEffectFade"
            }
        }
    }

    enum AspectRatio: String, CaseIterable, Identifiable {
        case portrait = "9:16"
        case square = "1:1"
        case landscape = "16:9"

        var id: String { rawValue }

        var ratio: CGFloat {
            switch self {
            case .portrait: return 9.0 / 16.0
            case .square: return 1.0
            case .landscape: return 16.0 / 9.0
            }
        }
    }

    // MARK: - Setup

    func setupSession() async {
        // Request permissions
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if videoStatus == .notDetermined {
            await AVCaptureDevice.requestAccess(for: .video)
        }

        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus == .notDetermined {
            await AVCaptureDevice.requestAccess(for: .audio)
        }

        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            error = .cameraUnavailable
            return
        }

        await configureSession()
    }

    private func configureSession() async {
        let configured = await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }

                self.captureSession.beginConfiguration()
                self.captureSession.sessionPreset = .hd1280x720

                // Video input
                guard let videoDevice = AVCaptureDevice.default(
                    .builtInWideAngleCamera,
                    for: .video,
                    position: self.isFrontCamera ? .front : .back
                ) else {
                    self.captureSession.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }

                do {
                    let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                    if self.captureSession.canAddInput(videoInput) {
                        self.captureSession.addInput(videoInput)
                        self.currentVideoInput = videoInput
                    } else {
                        self.captureSession.commitConfiguration()
                        continuation.resume(returning: false)
                        return
                    }
                } catch {
                    self.captureSession.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }

                // Audio input (optional)
                if let audioDevice = AVCaptureDevice.default(for: .audio) {
                    do {
                        let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                        if self.captureSession.canAddInput(audioInput) {
                            self.captureSession.addInput(audioInput)
                            self.audioInput = audioInput
                        }
                    } catch {
                        // Audio optional, continue without it
                    }
                }

                // Video output
                let movieOutput = AVCaptureMovieFileOutput()
                if self.captureSession.canAddOutput(movieOutput) {
                    self.captureSession.addOutput(movieOutput)
                    self.videoOutput = movieOutput
                }

                self.captureSession.commitConfiguration()

                // Create preview layer
                let layer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                layer.videoGravity = .resizeAspectFill

                Task { @MainActor in
                    self.previewLayer = layer
                }

                continuation.resume(returning: true)
            }
        }

        if configured {
            isConfigured = true
        } else {
            error = .cameraUnavailable
        }
    }

    func startSession() {
        guard isConfigured else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                Task { @MainActor in
                    self.isSessionRunning = true
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                Task { @MainActor in
                    self.isSessionRunning = false
                }
            }
        }
    }

    // MARK: - Recording

    func startRecording(maxDuration: TimeInterval) {
        guard !isRecording, let videoOutput else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "clip_\(UUID().uuidString).mov"
        let fileURL = tempDir.appendingPathComponent(fileName)
        tempVideoURL = fileURL

        currentClipStartTime = totalRecordedTime
        recordingTime = totalRecordedTime

        videoOutput.startRecording(to: fileURL, recordingDelegate: self)
        isRecording = true

        // Start timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.recordingTime += 0.1

                // Auto-stop at max duration
                if self.recordingTime >= maxDuration {
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        recordingTimer?.invalidate()
        recordingTimer = nil
        videoOutput?.stopRecording()
        isRecording = false
    }

    // MARK: - Camera Controls

    func flipCamera() {
        isFrontCamera.toggle()

        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.captureSession.beginConfiguration()

            // Remove current video input
            if let currentInput = self.currentVideoInput {
                self.captureSession.removeInput(currentInput)
            }

            // Add new video input
            guard let videoDevice = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: self.isFrontCamera ? .front : .back
            ) else {
                self.captureSession.commitConfiguration()
                return
            }

            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.captureSession.canAddInput(videoInput) {
                    self.captureSession.addInput(videoInput)
                    self.currentVideoInput = videoInput
                }
            } catch {
                // Failed to switch
            }

            self.captureSession.commitConfiguration()
        }
    }

    func toggleFlash() {
        guard let device = currentVideoInput?.device, device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            isFlashOn.toggle()
            device.torchMode = isFlashOn ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Flash toggle failed
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = currentVideoInput?.device else { return }

        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
        let clampedZoom = max(1.0, min(factor, maxZoom))

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedZoom
            device.unlockForConfiguration()
            zoomFactor = clampedZoom
            maxZoomFactor = maxZoom
        } catch {
            // Zoom failed
        }
    }

    // MARK: - Vlogger Controls

    func setExposure(_ value: Float) {
        guard let device = currentVideoInput?.device else { return }

        let clampedValue = max(-2.0, min(2.0, value))

        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clampedValue) { _ in }
            device.unlockForConfiguration()
            exposureValue = clampedValue
        } catch {
            // Exposure adjustment failed
        }
    }

    func setFocus(at point: CGPoint) {
        guard let device = currentVideoInput?.device else { return }
        guard device.isFocusPointOfInterestSupported else { return }

        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus
            device.exposurePointOfInterest = point
            device.exposureMode = .autoExpose
            device.unlockForConfiguration()

            focusPoint = point
            isFocusLocked = false
        } catch {
            // Focus failed
        }
    }

    func toggleFocusLock() {
        guard let device = currentVideoInput?.device else { return }

        do {
            try device.lockForConfiguration()
            if isFocusLocked {
                device.focusMode = .continuousAutoFocus
                device.exposureMode = .continuousAutoExposure
                isFocusLocked = false
            } else {
                device.focusMode = .locked
                device.exposureMode = .locked
                isFocusLocked = true
            }
            device.unlockForConfiguration()
        } catch {
            // Focus lock failed
        }
    }

    func startAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateAudioLevel()
            }
        }
        checkExternalMic()
    }

    func stopAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        audioLevel = 0
    }

    private func updateAudioLevel() {
        guard audioInput != nil else {
            audioLevel = 0
            return
        }

        // Get audio levels from the movie file output's audio connections
        if let connection = videoOutput?.connection(with: .audio) {
            // Use the audio channel's average power level
            if let channel = connection.audioChannels.first {
                let power = channel.averagePowerLevel
                // Convert dB to linear scale (0-1)
                let linear = pow(10, power / 20)
                audioLevel = min(1.0, max(0.0, linear * 2))
            }
        }
    }

    func checkExternalMic() {
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute

        isExternalMicConnected = currentRoute.inputs.contains { input in
            input.portType != .builtInMic
        }
    }

    func setMirrorPreview(_ mirror: Bool) {
        isMirrorPreview = mirror

        // Update preview layer connection mirroring
        if let connection = previewLayer?.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isFrontCamera && mirror
        }
    }

    // MARK: - Clip Management

    func deleteLastClip() {
        guard let lastClip = clips.popLast() else { return }
        try? FileManager.default.removeItem(at: lastClip.url)
    }

    func deleteAllClips() {
        for clip in clips {
            try? FileManager.default.removeItem(at: clip.url)
        }
        clips.removeAll()
        recordingTime = 0
    }

    // MARK: - Export

    func mergeClips() async throws -> URL {
        guard !clips.isEmpty else {
            throw CameraError.recordingFailed
        }

        // If only one clip, return it directly
        if clips.count == 1 {
            return clips[0].url
        }

        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw CameraError.recordingFailed
        }

        var currentTime = CMTime.zero

        for clip in clips {
            let asset = AVURLAsset(url: clip.url)

            if let videoAssetTrack = try? await asset.loadTracks(withMediaType: .video).first {
                let duration = try await asset.load(.duration)
                try videoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: videoAssetTrack,
                    at: currentTime
                )
            }

            if let audioAssetTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                let duration = try await asset.load(.duration)
                try? audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: audioAssetTrack,
                    at: currentTime
                )
            }

            let duration = try await asset.load(.duration)
            currentTime = CMTimeAdd(currentTime, duration)
        }

        // Export
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("merged_\(UUID().uuidString).mov")

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CameraError.recordingFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw CameraError.recordingFailed
        }

        return outputURL
    }
}

// MARK: - Recording Delegate

extension CameraSession: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            if error == nil {
                let duration = self.recordingTime - self.currentClipStartTime
                let clip = RecordedClip(url: outputFileURL, duration: duration)
                self.clips.append(clip)
            }
        }
    }
}
