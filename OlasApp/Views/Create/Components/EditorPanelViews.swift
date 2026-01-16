import CoreImage
import SwiftUI

// MARK: - Editor Toolbar

/// Toolbar for switching between editor panels
public struct EditorToolbar: View {
    @Binding var activePanel: EditorPanel?

    public init(activePanel: Binding<EditorPanel?>) {
        _activePanel = activePanel
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(EditorPanel.allCases, id: \.self) { panel in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        activePanel = activePanel == panel ? nil : panel
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: panel.icon)
                            .font(.system(size: 22))
                        Text(panel.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(activePanel == panel ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        activePanel == panel
                            ? Color(.systemGray5)
                            : Color.clear
                    )
                    .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - Crop Panel

/// Panel for cropping and rotating images
public struct CropPanel: View {
    @Binding var selectedAspectRatio: ImageAspectRatio
    @Binding var rotation: Double
    @Binding var isFlipped: Bool

    public init(
        selectedAspectRatio: Binding<ImageAspectRatio>,
        rotation: Binding<Double>,
        isFlipped: Binding<Bool>
    ) {
        _selectedAspectRatio = selectedAspectRatio
        _rotation = rotation
        _isFlipped = isFlipped
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Aspect ratios
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ImageAspectRatio.allCases) { ratio in
                        AspectRatioButton(
                            ratio: ratio,
                            isSelected: selectedAspectRatio == ratio
                        ) {
                            selectedAspectRatio = ratio
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Rotate & Flip buttons
            HStack(spacing: 12) {
                Button {
                    withAnimation {
                        rotation += 90
                    }
                } label: {
                    Label("Rotate", systemImage: "rotate.right")
                        .font(.system(size: 15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5))
                        .cornerRadius(12)
                }

                Button {
                    withAnimation {
                        isFlipped.toggle()
                    }
                } label: {
                    Label("Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .font(.system(size: 15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5))
                        .cornerRadius(12)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.bottom, 34)
        }
        .padding(.top, 8)
    }
}

// MARK: - Filters Panel

/// Panel for selecting image filters
public struct FiltersPanel: View {
    let sourceImage: UIImage
    @Binding var selectedFilter: ImageFilter
    @Binding var filterIntensity: Double
    let context: CIContext

    public init(
        sourceImage: UIImage,
        selectedFilter: Binding<ImageFilter>,
        filterIntensity: Binding<Double>,
        context: CIContext
    ) {
        self.sourceImage = sourceImage
        _selectedFilter = selectedFilter
        _filterIntensity = filterIntensity
        self.context = context
    }

    public var body: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ImageFilter.allCases) { filter in
                        FilterThumbnail(
                            filter: filter,
                            sourceImage: sourceImage,
                            isSelected: selectedFilter == filter,
                            context: context
                        ) {
                            selectedFilter = filter
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Intensity slider
            if selectedFilter != .original {
                VStack(spacing: 8) {
                    HStack {
                        Text("Intensity")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(filterIntensity * 100))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    Slider(value: $filterIntensity, in: 0 ... 1)
                        .tint(OlasTheme.Colors.accent)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            Spacer().frame(height: 34)
        }
        .padding(.top, 8)
    }
}

// MARK: - Adjust Panel

/// Panel for adjusting image properties
public struct AdjustPanel: View {
    @Binding var adjustments: [ImageAdjustment: Double]
    @Binding var selectedAdjustment: ImageAdjustment

    public init(
        adjustments: Binding<[ImageAdjustment: Double]>,
        selectedAdjustment: Binding<ImageAdjustment>
    ) {
        _adjustments = adjustments
        _selectedAdjustment = selectedAdjustment
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Adjustment grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(ImageAdjustment.allCases) { adjustment in
                    AdjustmentButton(
                        adjustment: adjustment,
                        isSelected: selectedAdjustment == adjustment,
                        hasValue: adjustments[adjustment] != nil && adjustments[adjustment] != adjustment.defaultValue
                    ) {
                        selectedAdjustment = adjustment
                    }
                }
            }
            .padding(.horizontal, 16)

            // Slider for selected adjustment
            VStack(spacing: 8) {
                HStack {
                    Text(selectedAdjustment.rawValue)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(selectedAdjustment.formatValue(adjustments[selectedAdjustment] ?? selectedAdjustment.defaultValue))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Slider(
                    value: Binding(
                        get: { adjustments[selectedAdjustment] ?? selectedAdjustment.defaultValue },
                        set: { adjustments[selectedAdjustment] = $0 }
                    ),
                    in: selectedAdjustment.range
                )
                .tint(OlasTheme.Colors.accent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer().frame(height: 34)
        }
        .padding(.top, 8)
    }
}
