import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - Image Editor View

struct ImageEditorView: View {
    @Binding var image: UIImage
    let onComplete: (UIImage) -> Void
    let onBack: () -> Void

    @State private var activePanel: EditorPanel? = .filters
    @State private var selectedFilter: ImageFilter = .original
    @State private var filterIntensity: Double = 1.0
    @State private var adjustments: [ImageAdjustment: Double] = [:]
    @State private var selectedAdjustment: ImageAdjustment = .brightness
    @State private var selectedAspectRatio: ImageAspectRatio = .square
    @State private var rotation: Double = 0
    @State private var isFlipped = false
    @State private var cropScale: CGFloat = 1.0
    @State private var cropCenter: CGPoint?
    @State private var dragStartCropCenter: CGPoint?
    @State private var magnifyStartCropScale: CGFloat?

    @State private var processedImage: UIImage?
    @State private var isProcessing = false

    /// Use shared context to avoid memory churn from recreating CIContext
    private var context: CIContext { FilterProcessor.sharedContext }

    init(image: Binding<UIImage>, onComplete: @escaping (UIImage) -> Void, onBack: @escaping () -> Void) {
        _image = image
        self.onComplete = onComplete
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                imagePreview
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                EditorToolbar(activePanel: $activePanel)

                if let panel = activePanel {
                    panelContent(for: panel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationTitle("Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isProcessing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Button("Next") {
                        Task {
                            await finalizeImage()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(OlasTheme.Colors.accent)
                }
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            Task { await updatePreview() }
        }
        .onChange(of: filterIntensity) { _, _ in
            Task { await updatePreview() }
        }
        .onChange(of: adjustments) { _, _ in
            Task { await updatePreview() }
        }
        .onChange(of: selectedAspectRatio) { _, _ in
            clampCropState()
            Task { await updatePreview() }
        }
        .onChange(of: activePanel) { oldValue, newValue in
            if oldValue == .crop, newValue != .crop {
                Task { await updatePreview() }
            }
        }
        .task {
            initializeCropStateIfNeeded()
            await updatePreview()
        }
    }

    // MARK: - Image Preview

    private var imagePreview: some View {
        GeometryReader { geometry in
            if activePanel == .crop {
                interactiveCropPreview(in: geometry.size)
            } else {
                let displayImage = processedImage ?? image
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .rotationEffect(.degrees(rotation))
                    .scaleEffect(x: isFlipped ? -1 : 1, y: 1)
                    .clipped()
                    .cornerRadius(8)
            }
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
    }

    @ViewBuilder
    private func interactiveCropPreview(in availableSize: CGSize) -> some View {
        let extent = sourceImageExtent()
        let cropFrame = cropFrameSize(in: availableSize, imageExtent: extent)
        let center = resolvedCropCenter(for: extent)
        let cropRect = FilterProcessor.cropRect(
            for: extent,
            aspectRatio: selectedAspectRatio,
            zoomScale: cropScale,
            center: center
        )
        let displayScale = cropFrame.width / max(cropRect.width, 1)
        let offsetX = (extent.midX - cropRect.midX) * displayScale
        let offsetY = (extent.midY - cropRect.midY) * displayScale

        ZStack {
            Color.black.opacity(0.9)

            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: max(extent.width, 1) * displayScale,
                    height: max(extent.height, 1) * displayScale
                )
                .scaleEffect(x: isFlipped ? -1 : 1, y: 1)
                .rotationEffect(.degrees(rotation))
                .offset(x: offsetX, y: offsetY)
        }
        .frame(width: cropFrame.width, height: cropFrame.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(cropInteractionGesture(cropFrameSize: cropFrame, extent: extent))
    }

    private func sourceImageExtent() -> CGRect {
        if let ciImage = CIImage(image: image) {
            return ciImage.extent
        }
        return CGRect(origin: .zero, size: image.size)
    }

    private func cropFrameSize(in availableSize: CGSize, imageExtent: CGRect) -> CGSize {
        let width = max(availableSize.width, 1)
        let height = max(availableSize.height, 1)
        let imageRatio = max(imageExtent.width, 1) / max(imageExtent.height, 1)
        let targetRatio = selectedAspectRatio.ratio ?? imageRatio
        let availableRatio = width / height

        if availableRatio > targetRatio {
            return CGSize(width: height * targetRatio, height: height)
        }
        return CGSize(width: width, height: width / targetRatio)
    }

    private func resolvedCropCenter(for extent: CGRect) -> CGPoint {
        cropCenter ?? CGPoint(x: extent.midX, y: extent.midY)
    }

    private func initializeCropStateIfNeeded() {
        guard cropCenter == nil else { return }
        let extent = sourceImageExtent()
        cropCenter = CGPoint(x: extent.midX, y: extent.midY)
        cropScale = min(max(cropScale, 1.0), 6.0)
    }

    private func clampCropState() {
        let extent = sourceImageExtent()
        cropScale = min(max(cropScale, 1.0), 6.0)
        let clampedRect = FilterProcessor.cropRect(
            for: extent,
            aspectRatio: selectedAspectRatio,
            zoomScale: cropScale,
            center: resolvedCropCenter(for: extent)
        )
        cropCenter = CGPoint(x: clampedRect.midX, y: clampedRect.midY)
    }

    private func cropInteractionGesture(cropFrameSize: CGSize, extent: CGRect) -> some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { value in
                    let startCenter = dragStartCropCenter ?? resolvedCropCenter(for: extent)
                    if dragStartCropCenter == nil {
                        dragStartCropCenter = startCenter
                    }

                    let cropRectAtStart = FilterProcessor.cropRect(
                        for: extent,
                        aspectRatio: selectedAspectRatio,
                        zoomScale: cropScale,
                        center: startCenter
                    )
                    let imageUnitsPerPointX = cropRectAtStart.width / max(cropFrameSize.width, 1)
                    let imageUnitsPerPointY = cropRectAtStart.height / max(cropFrameSize.height, 1)
                    let proposedCenter = CGPoint(
                        x: startCenter.x - value.translation.width * imageUnitsPerPointX,
                        y: startCenter.y - value.translation.height * imageUnitsPerPointY
                    )
                    let clampedRect = FilterProcessor.cropRect(
                        for: extent,
                        aspectRatio: selectedAspectRatio,
                        zoomScale: cropScale,
                        center: proposedCenter
                    )
                    cropCenter = CGPoint(x: clampedRect.midX, y: clampedRect.midY)
                }
                .onEnded { _ in
                    dragStartCropCenter = nil
                    Task { await updatePreview() }
                },
            MagnificationGesture()
                .onChanged { value in
                    let startScale = magnifyStartCropScale ?? cropScale
                    if magnifyStartCropScale == nil {
                        magnifyStartCropScale = startScale
                    }

                    cropScale = min(max(startScale * value, 1.0), 6.0)
                    let clampedRect = FilterProcessor.cropRect(
                        for: extent,
                        aspectRatio: selectedAspectRatio,
                        zoomScale: cropScale,
                        center: resolvedCropCenter(for: extent)
                    )
                    cropCenter = CGPoint(x: clampedRect.midX, y: clampedRect.midY)
                }
                .onEnded { _ in
                    magnifyStartCropScale = nil
                    Task { await updatePreview() }
                }
        )
    }

    // MARK: - Panel Content

    @ViewBuilder
    private func panelContent(for panel: EditorPanel) -> some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)

            switch panel {
            case .crop:
                CropPanel(
                    selectedAspectRatio: $selectedAspectRatio,
                    rotation: $rotation,
                    isFlipped: $isFlipped
                )
            case .filters:
                FiltersPanel(
                    sourceImage: image,
                    selectedFilter: $selectedFilter,
                    filterIntensity: $filterIntensity,
                    context: context
                )
            case .adjust:
                AdjustPanel(
                    adjustments: $adjustments,
                    selectedAdjustment: $selectedAdjustment
                )
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(20, corners: [.topLeft, .topRight])
    }

    // MARK: - Image Processing

    private func updatePreview() async {
        guard !isProcessing else { return }

        let filter = selectedFilter
        let intensity = filterIntensity
        let currentAdjustments = adjustments
        let aspectRatio = selectedAspectRatio
        let sourceImage = image
        let currentCropScale = cropScale
        let currentCropCenter = cropCenter

        let result = await Task.detached(priority: .userInitiated) {
            self.applyEdits(
                to: sourceImage,
                filter: filter,
                intensity: intensity,
                adjustments: currentAdjustments,
                aspectRatio: aspectRatio,
                cropScale: currentCropScale,
                cropCenter: currentCropCenter
            )
        }.value

        await MainActor.run {
            processedImage = result
        }
    }

    private func finalizeImage() async {
        isProcessing = true
        defer { isProcessing = false }

        let filter = selectedFilter
        let intensity = filterIntensity
        let currentAdjustments = adjustments
        let aspectRatio = selectedAspectRatio
        let sourceImage = image
        let currentRotation = rotation
        let flipped = isFlipped
        let currentCropScale = cropScale
        let currentCropCenter = cropCenter

        let result = await Task.detached(priority: .userInitiated) {
            var processed = self.applyEdits(
                to: sourceImage,
                filter: filter,
                intensity: intensity,
                adjustments: currentAdjustments,
                aspectRatio: aspectRatio,
                cropScale: currentCropScale,
                cropCenter: currentCropCenter
            )

            // Apply rotation and flip
            if currentRotation != 0 || flipped {
                processed = FilterProcessor.applyTransform(
                    to: processed ?? sourceImage,
                    rotation: currentRotation,
                    flip: flipped
                )
            }

            return processed
        }.value

        await MainActor.run {
            onComplete(result ?? image)
        }
    }

    private func applyEdits(
        to image: UIImage,
        filter: ImageFilter,
        intensity: Double,
        adjustments: [ImageAdjustment: Double],
        aspectRatio: ImageAspectRatio,
        cropScale: CGFloat,
        cropCenter: CGPoint?
    ) -> UIImage? {
        guard var ciImage = CIImage(image: image) else { return image }

        // Apply crop
        ciImage = FilterProcessor.applyCrop(
            to: ciImage,
            aspectRatio: aspectRatio,
            zoomScale: cropScale,
            center: cropCenter
        )

        // Apply filter
        if filter != .original {
            if let filtered = FilterProcessor.applyFilter(filter, to: ciImage, intensity: intensity) {
                ciImage = filtered
            }
        }

        // Apply adjustments
        ciImage = FilterProcessor.applyAdjustments(adjustments, to: ciImage)

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
