import NDKSwiftCore
import NDKSwiftUI
import PhotosUI
import SwiftUI

/// Sheet for creating a new follow pack
struct CreatePackSheet: View {
    let ndk: NDK
    let initialMember: String?
    let onCreated: () -> Void

    @Environment(FollowPackManager.self) private var packManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var selectedImage: PhotosPickerItem?
    @State private var imageURL: String?
    @State private var isUploading = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    init(ndk: NDK, initialMember: String? = nil, onCreated: @escaping () -> Void) {
        self.ndk = ndk
        self.initialMember = initialMember
        self.onCreated = onCreated
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating && !isUploading
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pack Name", text: $name)
                        .textInputAutocapitalization(.words)

                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Details")
                }

                Section {
                    imageSection
                } header: {
                    Text("Cover Image")
                } footer: {
                    Text("Optional cover image for your pack")
                }

                if let member = initialMember {
                    Section {
                        HStack(spacing: 12) {
                            NDKUIProfilePicture(ndk: ndk, pubkey: member, size: 40)
                                .clipShape(Circle())

                            VStack(alignment: .leading) {
                                Text(ndk.profile(for: member).displayName)
                                    .font(.body.weight(.medium))
                                Text("Will be added to this pack")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Initial Member")
                    }
                }
            }
            .navigationTitle("New Pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createPack() }
                    }
                    .disabled(!canCreate)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .overlay {
                if isCreating {
                    ProgressView("Creating pack...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
            }
        }
    }

    @ViewBuilder
    private var imageSection: some View {
        if let url = imageURL, let imageUrl = URL(string: url) {
            HStack {
                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()

                Button("Remove", role: .destructive) {
                    imageURL = nil
                    selectedImage = nil
                }
            }
        } else {
            PhotosPicker(selection: $selectedImage, matching: .images) {
                HStack {
                    Image(systemName: "photo.badge.plus")
                    Text("Select Image")
                }
            }
            .onChange(of: selectedImage) { _, newItem in
                Task { await uploadImage(newItem) }
            }

            if isUploading {
                HStack {
                    ProgressView()
                    Text("Uploading...")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func uploadImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        isUploading = true
        defer { isUploading = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                return
            }

            // Convert to UIImage and compress as JPEG
            guard let uiImage = UIImage(data: data),
                  let jpegData = ImageMetadataStripper.jpegDataWithoutMetadata(from: uiImage, compressionQuality: 0.8)
            else {
                errorMessage = "Failed to process image"
                return
            }

            // Get user's blossom servers or use defaults
            let blossomManager = NDKBlossomServerManager(ndk: ndk)
            var servers = blossomManager.userServers
            if servers.isEmpty {
                servers = OlasConstants.blossomServers
            }

            guard let serverUrl = servers.first else {
                errorMessage = "No upload server available"
                return
            }

            // Upload using BlossomClient with proper auth
            let client = BlossomClient()
            let blob = try await client.upload(
                data: jpegData,
                mimeType: "image/jpeg",
                to: serverUrl,
                ndk: ndk,
                configuration: .default
            )

            imageURL = blob.url
        } catch {
            errorMessage = "Failed to upload image: \(error.localizedDescription)"
        }
    }

    private func createPack() async {
        isCreating = true
        defer { isCreating = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            var initialMembers: [String] = []
            if let member = initialMember {
                initialMembers.append(member)
            }

            try await packManager.createPack(
                name: trimmedName,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                image: imageURL,
                initialMembers: initialMembers
            )

            dismiss()
            onCreated()
        } catch {
            errorMessage = "Failed to create pack: \(error.localizedDescription)"
        }
    }
}
