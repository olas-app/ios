import CoreImage
import SwiftUI

// MARK: - Aspect Ratio Button

/// Button for selecting an aspect ratio
public struct AspectRatioButton: View {
    let ratio: ImageAspectRatio
    let isSelected: Bool
    let onTap: () -> Void

    public init(ratio: ImageAspectRatio, isSelected: Bool, onTap: @escaping () -> Void) {
        self.ratio = ratio
        self.isSelected = isSelected
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? OlasTheme.Colors.accent : Color.secondary, lineWidth: 2)
                    .frame(width: ratioWidth, height: ratioHeight)

                Text(ratio.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? OlasTheme.Colors.accent.opacity(0.15)
                    : Color(.systemGray5)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? OlasTheme.Colors.accent : Color.clear, lineWidth: 2)
            )
        }
    }

    private var ratioWidth: CGFloat {
        switch ratio {
        case .square: return 32
        case .portrait: return 26
        case .landscape: return 32
        case .free: return 32
        }
    }

    private var ratioHeight: CGFloat {
        switch ratio {
        case .square: return 32
        case .portrait: return 32
        case .landscape: return 18
        case .free: return 24
        }
    }
}

// MARK: - Filter Thumbnail

/// Thumbnail preview of a filter
public struct FilterThumbnail: View {
    let filter: ImageFilter
    let sourceImage: UIImage
    let isSelected: Bool
    let context: CIContext
    let onTap: () -> Void

    @State private var thumbnail: UIImage?

    public init(
        filter: ImageFilter,
        sourceImage: UIImage,
        isSelected: Bool,
        context: CIContext,
        onTap: @escaping () -> Void
    ) {
        self.filter = filter
        self.sourceImage = sourceImage
        self.isSelected = isSelected
        self.context = context
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipped()
                    } else {
                        Color(.systemGray5)
                            .frame(width: 72, height: 72)
                    }
                }
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? OlasTheme.Colors.accent : Color.clear, lineWidth: 3)
                )

                Text(filter.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .task {
            await generateThumbnail()
        }
    }

    private func generateThumbnail() async {
        let size = CGSize(width: 144, height: 144)
        let renderer = UIGraphicsImageRenderer(size: size)
        let smallImage = renderer.image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: size))
        }

        if filter == .original {
            thumbnail = smallImage
            return
        }

        thumbnail = await Task.detached(priority: .utility) {
            guard let ciImage = CIImage(image: smallImage) else { return smallImage }

            let filtered = FilterProcessor.applyThumbnailFilter(filter, to: ciImage)

            guard let output = filtered,
                  let cgImage = context.createCGImage(output, from: output.extent)
            else {
                return smallImage
            }

            return UIImage(cgImage: cgImage)
        }.value
    }
}

// MARK: - Adjustment Button

/// Button for selecting an image adjustment
public struct AdjustmentButton: View {
    let adjustment: ImageAdjustment
    let isSelected: Bool
    let hasValue: Bool
    let onTap: () -> Void

    public init(
        adjustment: ImageAdjustment,
        isSelected: Bool,
        hasValue: Bool,
        onTap: @escaping () -> Void
    ) {
        self.adjustment = adjustment
        self.isSelected = isSelected
        self.hasValue = hasValue
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Image(systemName: adjustment.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? OlasTheme.Colors.accent : .secondary)

                    if hasValue {
                        Circle()
                            .fill(OlasTheme.Colors.accent)
                            .frame(width: 6, height: 6)
                            .offset(x: 12, y: -10)
                    }
                }

                Text(adjustment.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? OlasTheme.Colors.accent.opacity(0.15)
                    : Color(.systemGray5)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? OlasTheme.Colors.accent : Color.clear, lineWidth: 2)
            )
        }
    }
}
