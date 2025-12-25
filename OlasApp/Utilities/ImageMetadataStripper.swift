import CoreGraphics
import ImageIO
import UIKit

/// Utility for stripping EXIF and other metadata from images for privacy
/// This removes GPS location, camera info, timestamps, and other potentially sensitive data
enum ImageMetadataStripper {

    /// Strips all EXIF metadata from a UIImage and returns JPEG data
    /// - Parameters:
    ///   - image: The source UIImage
    ///   - compressionQuality: JPEG compression quality (0.0 - 1.0)
    /// - Returns: JPEG data with metadata stripped, or nil if conversion fails
    static func jpegDataWithoutMetadata(from image: UIImage, compressionQuality: CGFloat = 0.8) -> Data? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            return nil
        }

        // Properties to write - explicitly set metadata to nil/empty to strip it
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
            // Do not include any metadata dictionaries - this strips EXIF, GPS, TIFF, etc.
        ]

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }

    /// Strips metadata from existing image data (JPEG, PNG, etc.)
    /// - Parameters:
    ///   - data: The source image data
    ///   - outputType: The output image type (default: JPEG)
    ///   - compressionQuality: Compression quality for lossy formats
    /// - Returns: Image data with metadata stripped, or nil if processing fails
    static func stripMetadata(
        from data: Data,
        outputType: CFString = "public.jpeg" as CFString,
        compressionQuality: CGFloat = 0.8
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            outputType,
            1,
            nil
        ) else {
            return nil
        }

        // Write image without metadata
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
        ]

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }

    /// Checks if image data contains GPS metadata
    /// - Parameter data: The image data to check
    /// - Returns: True if GPS metadata is present
    static func containsGPSMetadata(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return false
        }

        return properties[kCGImagePropertyGPSDictionary] != nil
    }

    /// Checks if image data contains any EXIF metadata
    /// - Parameter data: The image data to check
    /// - Returns: True if EXIF metadata is present
    static func containsEXIFMetadata(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return false
        }

        return properties[kCGImagePropertyExifDictionary] != nil
    }
}
