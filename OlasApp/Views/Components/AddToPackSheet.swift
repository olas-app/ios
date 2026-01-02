import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

/// Sheet for adding a user to an existing pack or creating a new pack
struct AddToPackSheet: View {
    let ndk: NDK
    let userPubkey: String

    @Environment(FollowPackManager.self) private var packManager
    @Environment(\.dismiss) private var dismiss

    @State private var showCreatePack = false
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if packManager.isLoading {
                    ProgressView("Loading packs...")
                } else if packManager.userPacks.isEmpty {
                    emptyState
                } else {
                    packList
                }
            }
            .navigationTitle("Add to Pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreatePack = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreatePack) {
                CreatePackSheet(ndk: ndk, initialMember: userPubkey) {
                    dismiss()
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Packs", systemImage: "person.3")
        } description: {
            Text("Create your first follow pack to organize accounts you want to follow together.")
        } actions: {
            Button {
                showCreatePack = true
            } label: {
                Text("Create Pack")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var packList: some View {
        List {
            Section {
                ForEach(packManager.userPacks) { pack in
                    PackRow(
                        ndk: ndk,
                        pack: pack,
                        userPubkey: userPubkey,
                        isAdding: isAdding
                    ) {
                        await addToPack(pack)
                    }
                }
            } header: {
                Text("Your Packs")
            } footer: {
                Text("Select a pack to add this user, or create a new pack.")
            }
        }
    }

    private func addToPack(_ pack: FollowPack) async {
        isAdding = true
        defer { isAdding = false }

        do {
            try await packManager.addUserToPack(userPubkey, pack: pack)
            dismiss()
        } catch {
            errorMessage = "Failed to add user to pack: \(error.localizedDescription)"
        }
    }
}

// MARK: - Pack Row

private struct PackRow: View {
    let ndk: NDK
    let pack: FollowPack
    let userPubkey: String
    let isAdding: Bool
    let onAdd: () async -> Void

    private var isAlreadyInPack: Bool {
        pack.pubkeys.contains(userPubkey)
    }

    var body: some View {
        Button {
            Task { await onAdd() }
        } label: {
            HStack(spacing: 12) {
                // Pack image or gradient
                packImage
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("\(pack.memberCount) members")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isAlreadyInPack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if isAdding {
                    ProgressView()
                }
            }
        }
        .disabled(isAlreadyInPack || isAdding)
    }

    @ViewBuilder
    private var packImage: some View {
        if let imageURL = pack.image, let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    gradientPlaceholder
                }
            }
        } else {
            gradientPlaceholder
        }
    }

    private var gradientPlaceholder: some View {
        let hash = pack.name.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.3, brightness: 0.3),
                Color(hue: hue, saturation: 0.4, brightness: 0.5)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "person.3.fill")
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
