import NDKSwiftCore
import SwiftUI

struct FollowPackCardView: View {
    let followPack: FollowPack
    let ndk: NDK
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var creatorProfile: NDKUserMetadata?
    @State private var memberProfiles: [String: NDKUserMetadata] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with image/icon and name
            HStack(spacing: 12) {
                if let imageUrl = followPack.image, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        packPlaceholder
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    packPlaceholder
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(followPack.name)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text("\(followPack.memberCount) accounts")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let creator = creatorProfile?.name ?? creatorProfile?.displayName {
                            Text("by \(creator)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Selection indicator
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? OlasTheme.Colors.accent : .secondary)
                }
            }

            // Description
            if let description = followPack.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Member preview avatars
            if !memberProfiles.isEmpty {
                HStack(spacing: -8) {
                    ForEach(Array(memberProfiles.prefix(5)), id: \.key) { pubkey, profile in
                        memberAvatar(profile: profile)
                    }

                    if followPack.memberCount > 5 {
                        Text("+\(followPack.memberCount - 5)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? OlasTheme.Colors.accent : .clear, lineWidth: 2)
        )
        .task {
            await loadProfiles()
        }
    }

    private var packPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: "person.3.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            )
    }

    private func memberAvatar(profile: NDKUserMetadata) -> some View {
        Group {
            if let pictureUrl = profile.picture, let url = URL(string: pictureUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color(.systemGray5))
                }
            } else {
                Circle()
                    .fill(Color(.systemGray5))
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
    }

    private func loadProfiles() async {
        // Load creator profile
        for await metadata in await ndk.profileManager.subscribe(for: followPack.creatorPubkey, maxAge: 3600) {
            await MainActor.run {
                self.creatorProfile = metadata
            }
            break
        }

        // Load first 5 member profiles
        for pubkey in followPack.pubkeys.prefix(5) {
            for await metadata in await ndk.profileManager.subscribe(for: pubkey, maxAge: 3600) {
                await MainActor.run {
                    self.memberProfiles[pubkey] = metadata
                }
                break
            }
        }
    }
}
