import AVFoundation
import SwiftUI

// MARK: - Camera Preview View

/// SwiftUI wrapper for AVCaptureVideoPreviewLayer
public struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?

    public init(previewLayer: AVCaptureVideoPreviewLayer?) {
        self.previewLayer = previewLayer
    }

    public func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        return view
    }

    public func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.setPreviewLayer(previewLayer)
    }
}

// MARK: - Camera Preview UIView

/// UIKit view that hosts the camera preview layer
public class CameraPreviewUIView: UIView {
    private var currentPreviewLayer: AVCaptureVideoPreviewLayer?

    public override func layoutSubviews() {
        super.layoutSubviews()
        currentPreviewLayer?.frame = bounds
    }

    public func setPreviewLayer(_ previewLayer: AVCaptureVideoPreviewLayer?) {
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
