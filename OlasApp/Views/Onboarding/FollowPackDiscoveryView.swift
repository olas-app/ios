import NDKSwiftCore
import SwiftUI

struct FollowPackDiscoveryView: View {
    let ndk: NDK
    let onComplete: () -> Void

    @State private var followPacks: [FollowPack] = []
    @State private var selectedPackIds: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: Error?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Discover People to Follow")
                    .font(.title2.weight(.bold))

                Text("Select starter packs to populate your feed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Content
            if isLoading {
                Spacer()
                ProgressView("Finding follow packs...")
                Spacer()
            } else if followPacks.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No follow packs found")
                        .font(.headline)
                    Text("You can find people to follow later in Explore")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(followPacks) { pack in
                            FollowPackCardView(
                                followPack: pack,
                                ndk: ndk,
                                isSelected: selectedPackIds.contains(pack.id),
                                onToggle: {
                                    togglePack(pack)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
            }

            // Bottom button
            VStack(spacing: 12) {
                let selectedCount = selectedPackIds.count
                let totalPeople = followPacks
                    .filter { selectedPackIds.contains($0.id) }
                    .reduce(0) { $0 + $1.memberCount }

                if selectedCount > 0 {
                    Text("\(selectedCount) pack\(selectedCount == 1 ? "" : "s") selected (\(totalPeople) accounts)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await followSelectedPacks() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(selectedPackIds.isEmpty ? "Skip for Now" : "Follow \(totalPeople) Accounts")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        selectedPackIds.isEmpty
                            ? Color(.systemGray5)
                            : OlasTheme.Colors.accent
                    )
                    .foregroundStyle(selectedPackIds.isEmpty ? Color.primary : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .background(
                LinearGradient(
                    colors: [.clear, Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                .offset(y: -40),
                alignment: .top
            )
        }
        .task {
            await loadFollowPacks()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(error?.localizedDescription ?? "Failed to follow accounts")
        }
    }

    private func togglePack(_ pack: FollowPack) {
        if selectedPackIds.contains(pack.id) {
            selectedPackIds.remove(pack.id)
        } else {
            selectedPackIds.insert(pack.id)
        }
    }

    private func loadFollowPacks() async {
        isLoading = true
        defer { isLoading = false }

        // Subscribe to follow packs (kind 39089) and media follow packs (kind 39092)
        let filter = NDKFilter(
            kinds: [
                OlasConstants.EventKinds.followPack,
                OlasConstants.EventKinds.mediaFollowPack
            ],
            limit: 50
        )

        let subscription = ndk.subscribeWithTrace(filter: filter)

        var loadedPacks: [FollowPack] = []

        // Wait for up to 5 seconds collecting packs
        let deadline = Date().addingTimeInterval(5)
        for await events in subscription.events {
            guard !Task.isCancelled else { break }
            for event in events {
                if let pack = FollowPack(event: event), pack.memberCount > 0 {
                    loadedPacks.append(pack)
                }
            }
            if Date() > deadline || loadedPacks.count >= 20 {
                break
            }
        }

        // Sort by member count (most popular first) and deduplicate by name
        var seen = Set<String>()
        let uniquePacks = loadedPacks
            .sorted { $0.memberCount > $1.memberCount }
            .filter { pack in
                let key = pack.name.lowercased()
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }

        await MainActor.run {
            self.followPacks = Array(uniquePacks.prefix(20))
        }
    }

    private func followSelectedPacks() async {
        guard !selectedPackIds.isEmpty else {
            onComplete()
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            // Collect all unique pubkeys from selected packs
            var pubkeysToFollow = Set<String>()
            for pack in followPacks where selectedPackIds.contains(pack.id) {
                pubkeysToFollow.formUnion(pack.pubkeys)
            }

            // Build contact list event (kind 3)
            let pTags = pubkeysToFollow.map { ["p", $0] }

            _ = try await ndk.publish { builder in
                builder
                    .kind(Kind(OlasConstants.EventKinds.contactList))
                    .tags(pTags)
            }

            onComplete()
        } catch {
            self.error = error
            showError = true
        }
    }
}
