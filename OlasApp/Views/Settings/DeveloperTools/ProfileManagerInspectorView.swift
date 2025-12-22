import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

struct ProfileManagerInspectorView: View {
    let ndk: NDK

    @State private var cacheStats: (size: Int, hitRate: Double)?
    @State private var profileCacheCount: Int = 0
    @State private var searchPubkey: String = ""
    @State private var searchedProfile: NDKProfile?
    @State private var selectedProfile: (pubkey: String, profile: NDKProfile)?
    @State private var showingDetail = false
    @State private var isLoading = true
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading profile data...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Cache Stats Section
                Section("Cache Statistics") {
                    if let stats = cacheStats {
                        QuickStatRow(label: "Profile Manager Cache", value: "\(stats.size)")
                    }
                    QuickStatRow(label: "Profile Cache Count", value: "\(profileCacheCount)")
                    QuickStatRow(label: "Max Cache Size", value: "500")
                    QuickStatRow(label: "Memory Usage", value: String(format: "%.1f%%", Double(profileCacheCount) / 500.0 * 100))
                }

                // Profile Lookup Section
                Section("Profile Lookup") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter a public key (hex) to look up a profile:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("Public key (hex)", text: $searchPubkey)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            Task {
                                await lookupProfile()
                            }
                        } label: {
                            Label("Look Up Profile", systemImage: "magnifyingglass")
                        }
                        .disabled(searchPubkey.isEmpty)

                        if let profile = searchedProfile {
                            Divider()
                                .padding(.vertical, 4)

                            ProfileCacheRow(ndk: ndk, pubkey: searchPubkey, profile: profile)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedProfile = (searchPubkey, profile)
                                    showingDetail = true
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Info Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Profile Cache Info", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("The profile cache stores observable NDKProfile instances in an LRU cache. Individual profiles cannot be listed directly, but you can look up specific profiles by public key.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }

                // Actions Section
                Section("Actions") {
                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        Label("Clear All Caches", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Profile Manager")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
            .sheet(isPresented: $showingDetail) {
                if let item = selectedProfile {
                    NavigationStack {
                        ProfileDetailView(ndk: ndk, pubkey: item.pubkey, profile: item.profile)
                    }
                }
            }
            .alert("Clear Profile Caches", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    Task {
                        await clearCache()
                    }
                }
            } message: {
                Text("This will remove all cached profiles from memory (both ProfileManager and ProfileCache). Profiles will be re-fetched from the database or relays as needed.")
            }
    }

    private func loadData() async {
        isLoading = true

        // Get cache stats from profile manager
        cacheStats = await ndk.profileManager.getCacheStats()

        // Get profile cache count
        await MainActor.run {
            profileCacheCount = ndk.profileCache.count
        }

        isLoading = false
    }

    private func lookupProfile() async {
        guard !searchPubkey.isEmpty else { return }

        await MainActor.run {
            searchedProfile = ndk.profileCache.get(searchPubkey)
        }
    }

    private func clearCache() async {
        await ndk.profileManager.clearCache()
        await MainActor.run {
            ndk.profileCache.clearAll()
        }
        searchedProfile = nil
        await loadData()
    }
}

// MARK: - Supporting Views

private struct QuickStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Profile Cache Row

private struct ProfileCacheRow: View {
    let ndk: NDK
    let pubkey: String
    let profile: NDKProfile

    var body: some View {
        HStack(spacing: 12) {
            // Profile picture using NDKSwiftUI
            NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 50)

            VStack(alignment: .leading, spacing: 6) {
                // Display name using NDKSwiftUI
                HStack {
                    NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                        .font(.body)
                        .lineLimit(1)

                    Spacer()

                    // Has metadata indicator
                    if profile.metadata != nil {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                }

                // Pubkey
                Text(formatPubkey(pubkey))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Metadata preview
                if !profile.about.isEmpty {
                    Text(profile.about)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatPubkey(_ key: String) -> String {
        String(key.prefix(8)) + "..." + String(key.suffix(8))
    }
}

// MARK: - Profile Detail View

private struct ProfileDetailView: View {
    let ndk: NDK
    let pubkey: String
    let profile: NDKProfile

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Profile Header with NDKSwiftUI components
            Section {
                HStack(spacing: 16) {
                    // Profile picture
                    NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 80)

                    VStack(alignment: .leading, spacing: 8) {
                        // Display name
                        NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                            .font(.title2)
                            .fontWeight(.semibold)

                        // NIP-05 badge if available
                        if let nip05 = profile.nip05 {
                            Text(nip05)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            // Identity Section
            Section("Identity") {
                LabeledContent("Public Key") {
                    HStack {
                        Text(formatPubkey(pubkey))
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = pubkey
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                    }
                }
            }

            // Profile Details Section
            if hasProfileDetails {
                Section("Profile") {
                    if !profile.about.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("About")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(profile.about)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }

                    if let nip05 = profile.nip05 {
                        LabeledContent("NIP-05") {
                            Text(nip05)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }

            // Media Section
            if hasMedia {
                Section("Media") {
                    if let pictureURL = profile.pictureURL {
                        LabeledContent("Picture URL") {
                            Link("View", destination: pictureURL)
                                .font(.caption)
                        }
                    }

                    if let bannerURL = profile.bannerURL {
                        LabeledContent("Banner URL") {
                            Link("View", destination: bannerURL)
                                .font(.caption)
                        }
                    }
                }
            }

            // Lightning Section
            if hasLightning {
                Section("Lightning") {
                    if let lud16 = profile.lud16 {
                        LabeledContent("LUD-16") {
                            Text(lud16)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }

            // Actions Section
            Section {
                Button {
                    UIPasteboard.general.string = pubkey
                } label: {
                    Label("Copy Public Key", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    Task {
                        await clearFromCache()
                    }
                } label: {
                    Label("Remove from Cache", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Profile Details")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
    }

    private var hasProfileDetails: Bool {
        profile.about != nil || profile.nip05 != nil
    }

    private var hasMedia: Bool {
        profile.pictureURL != nil || profile.bannerURL != nil
    }

    private var hasLightning: Bool {
        profile.lud16 != nil
    }

    private func formatPubkey(_ key: String) -> String {
        String(key.prefix(16)) + "..." + String(key.suffix(16))
    }

    private func clearFromCache() async {
        await MainActor.run {
            ndk.profileCache.clear(pubkey)
        }
        dismiss()
    }
}
