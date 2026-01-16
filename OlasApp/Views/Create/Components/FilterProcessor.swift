import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - Filter Processor

/// Handles applying filters and adjustments to images
public enum FilterProcessor {
    /// Shared CIContext for efficient GPU-accelerated image processing
    /// Using a singleton avoids recreating the context on each view redraw
    public static let sharedContext = CIContext(options: [.useSoftwareRenderer: false])
    /// Applies a filter to an image with the given intensity
    public static func applyFilter(
        _ filter: ImageFilter,
        to image: CIImage,
        intensity: Double
    ) -> CIImage? {
        let filtered: CIImage?

        switch filter {
        case .original:
            return image

        case .clarendon:
            let contrast = CIFilter.colorControls()
            contrast.inputImage = image
            contrast.contrast = Float(1.0 + 0.2 * intensity)
            contrast.saturation = Float(1.0 + 0.35 * intensity)
            filtered = contrast.outputImage

        case .gingham:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.brightness = Float(0.05 * intensity)
            if let output = controls.outputImage {
                let hue = CIFilter.hueAdjust()
                hue.inputImage = output
                hue.angle = Float(-0.05 * intensity)
                filtered = hue.outputImage
            } else {
                filtered = nil
            }

        case .moon:
            let mono = CIFilter.photoEffectMono()
            mono.inputImage = image
            if let monoOutput = mono.outputImage {
                let contrast = CIFilter.colorControls()
                contrast.inputImage = monoOutput
                contrast.contrast = Float(1.0 + 0.1 * intensity)
                filtered = contrast.outputImage
            } else {
                filtered = nil
            }

        case .lark:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.contrast = Float(1.0 - 0.1 * intensity)
            controls.brightness = Float(0.1 * intensity)
            controls.saturation = Float(1.0 - 0.15 * intensity)
            filtered = controls.outputImage

        case .reyes:
            let sepia = CIFilter.sepiaTone()
            sepia.inputImage = image
            sepia.intensity = Float(0.22 * intensity)
            if let sepiaOutput = sepia.outputImage {
                let controls = CIFilter.colorControls()
                controls.inputImage = sepiaOutput
                controls.brightness = Float(0.1 * intensity)
                controls.contrast = Float(1.0 - 0.15 * intensity)
                controls.saturation = Float(1.0 - 0.25 * intensity)
                filtered = controls.outputImage
            } else {
                filtered = nil
            }

        case .juno:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.contrast = Float(1.0 + 0.1 * intensity)
            controls.brightness = Float(0.1 * intensity)
            controls.saturation = Float(1.0 + 0.4 * intensity)
            filtered = controls.outputImage

        case .slumber:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = Float(1.0 - 0.3 * intensity)
            controls.brightness = Float(-0.05 * intensity)
            filtered = controls.outputImage

        case .crema:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = Float(1.0 - 0.2 * intensity)
            if let output = controls.outputImage {
                let temp = CIFilter.temperatureAndTint()
                temp.inputImage = output
                temp.neutral = CIVector(x: 6500, y: 0)
                temp.targetNeutral = CIVector(x: 6500 - 500 * intensity, y: 0)
                filtered = temp.outputImage
            } else {
                filtered = nil
            }

        case .ludwig:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = Float(1.0 - 0.15 * intensity)
            controls.contrast = Float(1.0 + 0.05 * intensity)
            filtered = controls.outputImage

        case .aden:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = Float(1.0 - 0.2 * intensity)
            controls.contrast = Float(1.0 - 0.1 * intensity)
            if let output = controls.outputImage {
                let hue = CIFilter.hueAdjust()
                hue.inputImage = output
                hue.angle = Float(0.05 * intensity)
                filtered = hue.outputImage
            } else {
                filtered = nil
            }

        case .perpetua:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = Float(1.0 + 0.1 * intensity)
            if let output = controls.outputImage {
                let temp = CIFilter.temperatureAndTint()
                temp.inputImage = output
                temp.neutral = CIVector(x: 6500, y: 0)
                temp.targetNeutral = CIVector(x: 7500, y: 0)
                filtered = temp.outputImage
            } else {
                filtered = nil
            }
        }

        // Blend with original based on intensity
        if let filtered, intensity < 1.0 {
            let blend = CIFilter.dissolveTransition()
            blend.inputImage = image
            blend.targetImage = filtered
            blend.time = Float(intensity)
            return blend.outputImage
        }

        return filtered
    }

    /// Applies a simplified filter for thumbnail generation
    public static func applyThumbnailFilter(_ filter: ImageFilter, to ciImage: CIImage) -> CIImage? {
        switch filter {
        case .original:
            return ciImage
        case .clarendon:
            let f = CIFilter.colorControls()
            f.inputImage = ciImage
            f.contrast = 1.2
            f.saturation = 1.35
            return f.outputImage
        case .moon:
            let f = CIFilter.photoEffectMono()
            f.inputImage = ciImage
            return f.outputImage
        case .gingham:
            let f = CIFilter.colorControls()
            f.inputImage = ciImage
            f.brightness = 0.05
            return f.outputImage
        case .lark:
            let f = CIFilter.colorControls()
            f.inputImage = ciImage
            f.contrast = 0.9
            f.brightness = 0.1
            f.saturation = 0.85
            return f.outputImage
        case .reyes:
            let f = CIFilter.sepiaTone()
            f.inputImage = ciImage
            f.intensity = 0.22
            return f.outputImage
        case .juno:
            let f = CIFilter.colorControls()
            f.inputImage = ciImage
            f.contrast = 1.1
            f.saturation = 1.4
            return f.outputImage
        case .slumber:
            let f = CIFilter.colorControls()
            f.inputImage = ciImage
            f.saturation = 0.7
            f.brightness = -0.05
            return f.outputImage
        case .crema:
            let f = CIFilter.colorControls()
            f.inputImage = ciImage
            f.saturation = 0.8
            return f.outputImage
        case .ludwig:
            let f = CIFilter.colorControls()
            f.inputImage = ciImage
            f.saturation = 0.85
            f.contrast = 1.05
            return f.outputImage
        case .aden:
            let f = CIFilter.colorControls()
            f.inputImage = ciImage
            f.saturation = 0.8
            f.contrast = 0.9
            return f.outputImage
        case .perpetua:
            let f = CIFilter.colorControls()
            f.inputImage = ciImage
            f.saturation = 1.1
            return f.outputImage
        }
    }

    /// Applies adjustments to an image
    public static func applyAdjustments(
        _ adjustments: [ImageAdjustment: Double],
        to image: CIImage
    ) -> CIImage {
        var result = image

        // Color controls (brightness, contrast, saturation)
        let brightness = adjustments[.brightness] ?? 0
        let contrast = adjustments[.contrast] ?? 1
        let saturation = adjustments[.saturation] ?? 1

        if brightness != 0 || contrast != 1 || saturation != 1 {
            let controls = CIFilter.colorControls()
            controls.inputImage = result
            controls.brightness = Float(brightness)
            controls.contrast = Float(contrast)
            controls.saturation = Float(saturation)
            result = controls.outputImage ?? result
        }

        // Warmth
        if let warmth = adjustments[.warmth], warmth != 0 {
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = result
            temp.neutral = CIVector(x: 6500, y: 0)
            temp.targetNeutral = CIVector(x: 6500 - warmth * 2000, y: 0)
            result = temp.outputImage ?? result
        }

        // Highlights and shadows
        let shadows = adjustments[.shadows] ?? 0
        let highlights = adjustments[.highlights] ?? 0
        if shadows != 0 || highlights != 0 {
            let highlightShadow = CIFilter.highlightShadowAdjust()
            highlightShadow.inputImage = result
            highlightShadow.shadowAmount = Float(1 + shadows)
            highlightShadow.highlightAmount = Float(1 - highlights)
            result = highlightShadow.outputImage ?? result
        }

        // Vignette
        if let vignette = adjustments[.vignette], vignette > 0 {
            let vignetteFilter = CIFilter.vignette()
            vignetteFilter.inputImage = result
            vignetteFilter.intensity = Float(vignette)
            vignetteFilter.radius = Float(vignette * 2)
            result = vignetteFilter.outputImage ?? result
        }

        // Sharpen
        if let sharpen = adjustments[.sharpen], sharpen > 0 {
            let sharpenFilter = CIFilter.sharpenLuminance()
            sharpenFilter.inputImage = result
            sharpenFilter.sharpness = Float(sharpen * 0.5)
            result = sharpenFilter.outputImage ?? result
        }

        return result
    }

    /// Applies crop based on aspect ratio
    public static func applyCrop(to image: CIImage, aspectRatio: ImageAspectRatio) -> CIImage {
        guard let targetRatio = aspectRatio.ratio else {
            return image
        }

        let extent = image.extent
        let currentRatio = extent.width / extent.height

        var cropRect = extent

        if currentRatio > targetRatio {
            // Image is wider than target, crop width
            let newWidth = extent.height * targetRatio
            let xOffset = (extent.width - newWidth) / 2
            cropRect = CGRect(x: extent.origin.x + xOffset, y: extent.origin.y, width: newWidth, height: extent.height)
        } else if currentRatio < targetRatio {
            // Image is taller than target, crop height
            let newHeight = extent.width / targetRatio
            let yOffset = (extent.height - newHeight) / 2
            cropRect = CGRect(x: extent.origin.x, y: extent.origin.y + yOffset, width: extent.width, height: newHeight)
        }

        if cropRect != extent {
            var cropped = image.cropped(to: cropRect)
            cropped = cropped.transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
            return cropped
        }

        return image
    }

    /// Applies rotation and flip transforms
    public static func applyTransform(to image: UIImage, rotation: Double, flip: Bool) -> UIImage? {
        let radians = rotation * .pi / 180

        let size = image.size
        let rotatedSize: CGSize

        // Normalize rotation to 0-359 range and check if 90° or 270° (portrait orientation)
        let normalizedRotation = Int(rotation.truncatingRemainder(dividingBy: 360) + 360) % 360
        if normalizedRotation == 90 || normalizedRotation == 270 {
            rotatedSize = CGSize(width: size.height, height: size.width)
        } else {
            rotatedSize = size
        }

        UIGraphicsBeginImageContextWithOptions(rotatedSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return image }

        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.rotate(by: radians)
        if flip {
            context.scaleBy(x: -1, y: 1)
        }
        context.translateBy(x: -size.width / 2, y: -size.height / 2)

        image.draw(at: .zero)

        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return result
    }
}
