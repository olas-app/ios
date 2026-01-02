import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

/// Full vertical list view for all discovered follow packs
struct FollowPacksListView: View {
    let ndk: NDK
    let packs: [FollowPack]

    @Environment(SavedFeedSourcesManager.self) private var feedSourcesManager

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(packs) { pack in
                    NavigationLink(value: pack) {
                        FollowPackListRow(ndk: ndk, pack: pack)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Follow Packs")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Follow Pack List Row

private struct FollowPackListRow: View {
    let ndk: NDK
    let pack: FollowPack

    @Environment(SavedFeedSourcesManager.self) private var feedSourcesManager

    @State private var creatorProfile: NDKProfile?

    private var isSaved: Bool {
        feedSourcesManager.savedPacks.contains { $0.id == pack.id }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Pack image or gradient
            packImage
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(pack.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if pack.event.kind == OlasConstants.EventKinds.mediaFollowPack {
                        Image(systemName: "photo.stack")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let description = pack.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    Label("\(pack.memberCount)", systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let profile = creatorProfile {
                        HStack(spacing: 4) {
                            Text("by")
                                .foregroundStyle(.tertiary)
                            Text(profile.displayName)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Member avatars
            memberAvatars
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            creatorProfile = ndk.profile(for: pack.creatorPubkey)
        }
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
                .font(.title2)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var memberAvatars: some View {
        HStack(spacing: -8) {
            ForEach(Array(pack.pubkeys.prefix(3).enumerated()), id: \.element) { _, pubkey in
                NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 28)
                    .overlay {
                        Circle()
                            .stroke(Color(.secondarySystemBackground), lineWidth: 2)
                    }
            }
        }
    }
}
