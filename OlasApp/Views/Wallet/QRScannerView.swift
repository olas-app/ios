import AVFoundation
import SwiftUI

// MARK: - QR Scanner View

struct QRScannerView: View {
    let onScan: (String) -> Void

    @State private var cameraPermission: CameraPermission = .undetermined
    @State private var hasScanned = false

    enum CameraPermission {
        case undetermined
        case authorized
        case denied
    }

    var body: some View {
        ZStack {
            switch cameraPermission {
            case .authorized:
                QRCameraView(onScan: handleScan)
                    .ignoresSafeArea()

                // Scanning overlay
                VStack {
                    Spacer()

                    Text("Point camera at QR code")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.black.opacity(0.7))
                        .cornerRadius(10)
                        .padding()
                }

            case .denied:
                permissionDeniedView

            case .undetermined:
                ProgressView("Requesting camera access...")
                    .foregroundStyle(.primary)
            }
        }
        .background(Color(.systemBackground))
        .task {
            await requestCameraPermission()
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Camera Access Required")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text("Please enable camera access in Settings to scan QR codes.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                Button {
                    UIApplication.shared.open(settingsUrl)
                } label: {
                    Text("Open Settings")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OlasTheme.Colors.accent)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.top)
            }
        }
        .padding()
    }

    private func requestCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            cameraPermission = .authorized

        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraPermission = granted ? .authorized : .denied

        case .denied, .restricted:
            cameraPermission = .denied

        @unknown default:
            cameraPermission = .denied
        }
    }

    private func handleScan(_ code: String) {
        guard !hasScanned else { return }
        hasScanned = true

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        onScan(code)
    }
}

// MARK: - Camera View

struct QRCameraView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context _: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_: CameraViewController, context _: Context) {}
}

// MARK: - Camera View Controller

class CameraViewController: UIViewController {
    var onScan: ((String) -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScannedCode = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopSession()
    }

    private func setupCamera() {
        let session = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            return
        }

        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        captureSession = session
        self.previewLayer = previewLayer
    }

    private func startSession() {
        guard let captureSession = captureSession, !captureSession.isRunning else {
            return
        }

        hasScannedCode = false

        Task.detached { [weak captureSession] in
            captureSession?.startRunning()
        }
    }

    private func stopSession() {
        guard let captureSession = captureSession, captureSession.isRunning else {
            return
        }

        Task.detached { [weak captureSession] in
            captureSession?.stopRunning()
        }
    }
}

// MARK: - Metadata Output Delegate

extension CameraViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from _: AVCaptureConnection) {
        guard !hasScannedCode else { return }

        if let metadataObject = metadataObjects.first,
           let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
           let stringValue = readableObject.stringValue
        {
            hasScannedCode = true
            stopSession()
            onScan?(stringValue)
        }
    }
}
