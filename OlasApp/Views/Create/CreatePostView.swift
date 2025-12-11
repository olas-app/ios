import SwiftUI
import PhotosUI
import NDKSwiftCore
import UnifiedBlurHash

public struct CreatePostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PublishingState.self) private var publishingState
    let ndk: NDK

    @State private var selectedImage: UIImage?
    @State private var editedImage: UIImage?
    @State private var caption = ""
    @State private var error: Error?
    @State private var showError = false

    @State private var step: PostCreationStep = .selectPhoto

    enum PostCreationStep {
        case selectPhoto
        case editPhoto
        case addCaption
    }

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Group {
                    switch step {
                    case .selectPhoto:
                        PhotoLibraryView(
                            selectedImage: $selectedImage,
                            onNext: {
                                if selectedImage != nil {
                                    step = .editPhoto
                                }
                            },
                            onCancel: {
                                dismiss()
                            }
                        )

                    case .editPhoto:
                        if let image = Binding($selectedImage) {
                            ImageEditorView(
                                image: image,
                                onComplete: { finalImage in
                                    editedImage = finalImage
                                    step = .addCaption
                                },
                                onBack: {
                                    step = .selectPhoto
                                }
                            )
                        }

                    case .addCaption:
                        if let image = editedImage ?? selectedImage {
                            CaptionView(
                                image: image,
                                caption: $caption,
                                onShare: {
                                    Task {
                                        await publishPost()
                                    }
                                },
                                onBack: {
                                    step = .editPhoto
                                }
                            )
                        }
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {
                    step = .addCaption
                }
            } message: {
                Text(error?.localizedDescription ?? "Unknown error")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func publishPost() async {
        guard let image = editedImage ?? selectedImage else { return }

        let service = PostPublishingService(ndk: ndk)

        // Start background publishing
        Task {
            publishingState.isPublishing = true
            publishingState.error = nil

            do {
                let eventId = try await service.publish(
                    image: image,
                    caption: caption,
                    onProgress: { status, progress in
                        publishingState.publishingStatus = status
                        publishingState.publishingProgress = progress
                    }
                )

                publishingState.lastPublishedEventId = eventId

                // Auto-hide after 2 seconds
                try? await Task.sleep(for: .seconds(2))
                publishingState.reset()
            } catch {
                publishingState.error = error
                publishingState.publishingStatus = "Failed: \(error.localizedDescription)"
            }
        }

        // Immediately dismiss the view
        await MainActor.run {
            dismiss()
        }
    }
}

// Helper extension for optional binding
extension Binding {
    init?(_ source: Binding<Value?>) {
        guard source.wrappedValue != nil else { return nil }
        self.init(
            get: { source.wrappedValue! },
            set: { source.wrappedValue = $0 }
        )
    }
}
