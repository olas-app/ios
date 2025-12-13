import NDKSwiftCore
import SwiftUI

/// Header section of the profile showing name and about
struct ProfileHeaderView: View {
    let profile: NDKUserMetadata?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile?.name ?? "Unknown")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)

            if let about = profile?.about, !about.isEmpty {
                Text(about)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

/// Stats section showing post count and following count
struct ProfileStatsView: View {
    let postCount: Int
    let followingCount: Int

    var body: some View {
        HStack(spacing: 32) {
            StatItem(count: postCount, label: "Posts")
            StatItem(count: followingCount, label: "Following")
        }
    }
}

/// Individual stat item
private struct StatItem: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

/// Action button for edit profile or mute/unmute
struct ProfileActionButton: View {
    let isOwnProfile: Bool
    let isMuted: Bool
    let action: () -> Void

    private var buttonText: String {
        if isOwnProfile {
            return "Edit Profile"
        } else {
            return isMuted ? "Unmute" : "Mute"
        }
    }

    var body: some View {
        Button(action: action) {
            Text(buttonText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray5))
                .cornerRadius(10)
        }
    }
}
