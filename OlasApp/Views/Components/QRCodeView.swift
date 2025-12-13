import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeView: View {
    let content: String
    let size: CGFloat

    var body: some View {
        let _ = print("[QRCodeView] Generating QR code for content length: \(content.count), prefix: \(content.prefix(20))")

        if let qrImage = generateQRCode(from: content) {
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            let _ = print("[QRCodeView] ERROR: Failed to generate QR code for: \(content)")
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Text("Unable to generate QR code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                )
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: .utf8)
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = data ?? Data()
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        let scale = UIScreen.main.scale
        let transform = CGAffineTransform(scaleX: scale * 10, y: scale * 10)
        let scaledCIImage = ciImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledCIImage, from: scaledCIImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
