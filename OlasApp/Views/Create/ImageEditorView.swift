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
            Task { await updatePreview() }
        }
        .task {
            await updatePreview()
        }
    }

    // MARK: - Image Preview

    private var imagePreview: some View {
        GeometryReader { _ in
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
        .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
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

        let result = await Task.detached(priority: .userInitiated) {
            self.applyEdits(
                to: sourceImage,
                filter: filter,
                intensity: intensity,
                adjustments: currentAdjustments,
                aspectRatio: aspectRatio
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

        let result = await Task.detached(priority: .userInitiated) {
            var processed = self.applyEdits(
                to: sourceImage,
                filter: filter,
                intensity: intensity,
                adjustments: currentAdjustments,
                aspectRatio: aspectRatio
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
        aspectRatio: ImageAspectRatio
    ) -> UIImage? {
        guard var ciImage = CIImage(image: image) else { return image }

        // Apply crop
        ciImage = FilterProcessor.applyCrop(to: ciImage, aspectRatio: aspectRatio)

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
