# Onboarding with Follow Packs Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a modern onboarding flow that guides new users through profile creation (kind:0) and discovering follow packs (kind 39089/39092) to populate their feed.

**Architecture:** After account creation, users are taken through a multi-step onboarding:
1. Set up their profile (display name, optional picture)
2. Browse and select follow packs (kind 39089 for general, 39092 for media-focused)
3. Complete onboarding and land on feed with curated follows

**Tech Stack:** SwiftUI, NDK (for Nostr events), async/await, @Observable

---

## Task 1: Add Follow Pack Event Kinds to Constants

**Files:**
- Modify: `OlasApp/Models/OlasConstants.swift:17-25`

**Step 1: Add follow pack kind constants**

Add to `OlasConstants.EventKinds`:
```swift
public static let followPack: NDKSwiftCore.Kind = 39089
public static let mediaFollowPack: NDKSwiftCore.Kind = 39092
public static let contactList: NDKSwiftCore.Kind = 3
```

**Step 2: Build to verify**

Run: `vibe-tools xcode build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add OlasApp/Models/OlasConstants.swift
git commit -m "feat: add follow pack (39089/39092) and contact list (3) event kinds"
```

---

## Task 2: Create FollowPack Model

**Files:**
- Create: `OlasApp/Models/FollowPack.swift`

**Step 1: Create the model file**

```swift
import Foundation
import NDKSwiftCore

struct FollowPack: Identifiable, Sendable {
    let id: String
    let event: NDKEvent
    let name: String
    let description: String?
    let image: String?
    let pubkeys: [String]
    let creatorPubkey: String

    init?(event: NDKEvent) {
        guard event.kind == OlasConstants.EventKinds.followPack ||
              event.kind == OlasConstants.EventKinds.mediaFollowPack else {
            return nil
        }

        self.id = event.id
        self.event = event
        self.creatorPubkey = event.pubkey

        // Extract name from "d" tag (required per NIP-51)
        guard let dTag = event.tags.first(where: { $0.first == "d" }),
              dTag.count > 1 else {
            return nil
        }
        self.name = dTag[1]

        // Extract description from "description" tag or content
        if let descTag = event.tags.first(where: { $0.first == "description" }),
           descTag.count > 1 {
            self.description = descTag[1]
        } else if !event.content.isEmpty {
            self.description = event.content
        } else {
            self.description = nil
        }

        // Extract image from "image" tag
        if let imageTag = event.tags.first(where: { $0.first == "image" }),
           imageTag.count > 1 {
            self.image = imageTag[1]
        } else {
            self.image = nil
        }

        // Extract pubkeys from "p" tags
        self.pubkeys = event.tags
            .filter { $0.first == "p" && $0.count > 1 }
            .compactMap { $0[1] }
    }

    var memberCount: Int {
        pubkeys.count
    }
}
```

**Step 2: Build to verify**

Run: `vibe-tools xcode build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add OlasApp/Models/FollowPack.swift
git commit -m "feat: add FollowPack model for kind 39089/39092 events"
```

---

## Task 3: Create Follow Pack Card View

**Files:**
- Create: `OlasApp/Views/Onboarding/FollowPackCardView.swift`

**Step 1: Create the card view**

```swift
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
```

**Step 2: Build to verify**

Run: `vibe-tools xcode build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add OlasApp/Views/Onboarding/FollowPackCardView.swift
git commit -m "feat: add FollowPackCardView for displaying follow pack cards"
```

---

## Task 4: Create Profile Setup View for Onboarding

**Files:**
- Create: `OlasApp/Views/Onboarding/ProfileSetupView.swift`

**Step 1: Create the profile setup view**

```swift
import NDKSwiftCore
import SwiftUI

struct ProfileSetupView: View {
    let ndk: NDK
    let onComplete: () -> Void

    @State private var displayName = ""
    @State private var about = ""
    @State private var isSaving = false
    @State private var error: Error?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(OlasTheme.Colors.accent)

                Text("Set Up Your Profile")
                    .font(.title2.weight(.bold))

                Text("Tell others a bit about yourself")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Form
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Name")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("Your name", text: $displayName)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("About (optional)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("A short bio", text: $about, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...4)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)

            Spacer()

            // Continue button
            VStack(spacing: 12) {
                Button {
                    Task { await saveProfile() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text(displayName.isEmpty ? "Skip for Now" : "Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(
                    displayName.isEmpty
                        ? Color(.systemGray5)
                        : OlasTheme.Colors.accent
                )
                .foregroundStyle(displayName.isEmpty ? .primary : .white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(isSaving)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(error?.localizedDescription ?? "Failed to save profile")
        }
    }

    private func saveProfile() async {
        // If skipping, just continue
        guard !displayName.isEmpty else {
            onComplete()
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            var metadata: [String: String] = [
                "display_name": displayName,
                "name": displayName
            ]

            if !about.isEmpty {
                metadata["about"] = about
            }

            let jsonData = try JSONSerialization.data(withJSONObject: metadata)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            _ = try await ndk.publish { builder in
                builder
                    .kind(EventKind.metadata)
                    .content(jsonString)
            }

            onComplete()
        } catch {
            self.error = error
            showError = true
        }
    }
}
```

**Step 2: Build to verify**

Run: `vibe-tools xcode build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add OlasApp/Views/Onboarding/ProfileSetupView.swift
git commit -m "feat: add ProfileSetupView for onboarding profile creation"
```

---

## Task 5: Create Follow Pack Discovery View

**Files:**
- Create: `OlasApp/Views/Onboarding/FollowPackDiscoveryView.swift`

**Step 1: Create the discovery view**

```swift
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
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text(selectedPackIds.isEmpty ? "Skip for Now" : "Follow \(totalPeople) Accounts")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(
                    selectedPackIds.isEmpty
                        ? Color(.systemGray5)
                        : OlasTheme.Colors.accent
                )
                .foregroundStyle(selectedPackIds.isEmpty ? .primary : .white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
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

        // Use a timeout to avoid waiting forever
        let subscription = ndk.subscribe(filter: filter)

        var loadedPacks: [FollowPack] = []
        let timeout = Task {
            try await Task.sleep(for: .seconds(5))
            return true
        }

        let loading = Task {
            for await event in subscription {
                if let pack = FollowPack(event: event), pack.memberCount > 0 {
                    loadedPacks.append(pack)
                }
            }
            return false
        }

        // Wait for either timeout or enough packs
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            if loadedPacks.count >= 10 {
                break
            }
        }

        timeout.cancel()
        loading.cancel()

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
```

**Step 2: Build to verify**

Run: `vibe-tools xcode build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add OlasApp/Views/Onboarding/FollowPackDiscoveryView.swift
git commit -m "feat: add FollowPackDiscoveryView for discovering kind 39089 follow packs"
```

---

## Task 6: Create Onboarding Flow Container

**Files:**
- Create: `OlasApp/Views/Onboarding/OnboardingFlowView.swift`

**Step 1: Create the flow container**

```swift
import NDKSwiftCore
import SwiftUI

struct OnboardingFlowView: View {
    let ndk: NDK
    let onComplete: () -> Void

    @State private var currentStep: OnboardingStep = .profile

    enum OnboardingStep {
        case profile
        case followPacks
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                progressDot(isActive: true)
                progressDot(isActive: currentStep == .followPacks)
            }
            .padding(.top, 16)

            // Content
            switch currentStep {
            case .profile:
                ProfileSetupView(ndk: ndk) {
                    withAnimation {
                        currentStep = .followPacks
                    }
                }

            case .followPacks:
                FollowPackDiscoveryView(ndk: ndk) {
                    onComplete()
                }
            }
        }
    }

    private func progressDot(isActive: Bool) -> some View {
        Capsule()
            .fill(isActive ? OlasTheme.Colors.accent : Color(.systemGray5))
            .frame(width: isActive ? 24 : 8, height: 8)
            .animation(.easeInOut, value: isActive)
    }
}
```

**Step 2: Build to verify**

Run: `vibe-tools xcode build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add OlasApp/Views/Onboarding/OnboardingFlowView.swift
git commit -m "feat: add OnboardingFlowView container for multi-step onboarding"
```

---

## Task 7: Add Onboarding Completed Flag to Settings

**Files:**
- Modify: `OlasApp/Utilities/SettingsManager.swift`

**Step 1: Add the flag**

Add to SettingsManager class:
```swift
@AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
```

**Step 2: Build to verify**

Run: `vibe-tools xcode build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add OlasApp/Utilities/SettingsManager.swift
git commit -m "feat: add hasCompletedOnboarding flag to SettingsManager"
```

---

## Task 8: Integrate Onboarding Flow into App

**Files:**
- Modify: `OlasApp/OlasApp.swift`

**Step 1: Update app body to include onboarding flow**

In the WindowGroup body, after `authViewModel.isLoggedIn` check but before MainTabView, add the onboarding condition:

Replace the logged-in branch:
```swift
} else if let ndk = ndk, let sparkWalletManager = sparkWalletManager, let nwcWalletManager = nwcWalletManager {
    if !settings.hasCompletedOnboarding {
        OnboardingFlowView(ndk: ndk) {
            settings.hasCompletedOnboarding = true
        }
        .environmentObject(authViewModel)
        .environment(\.ndk, ndk)
        .environment(settings)
    } else {
        MainTabView(ndk: ndk, sparkWalletManager: sparkWalletManager, nwcWalletManager: nwcWalletManager)
            .environmentObject(authViewModel)
            .environment(\.ndk, ndk)
            .environment(settings)
            .environment(relayCache)
            .environment(imageCache)
            .environment(publishingState)
    }
}
```

**Step 2: Reset onboarding flag on logout**

In `onChange(of: authViewModel.isLoggedIn)`, when logging out:
```swift
.onChange(of: authViewModel.isLoggedIn) { _, isLoggedIn in
    if isLoggedIn {
        ndk?.signer = authViewModel.signer
    } else {
        ndk?.signer = nil
        settings.hasCompletedOnboarding = false
    }
}
```

**Step 3: Build to verify**

Run: `vibe-tools xcode build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add OlasApp/OlasApp.swift
git commit -m "feat: integrate OnboardingFlowView into app after login"
```

---

## Task 9: Fix Profile "Unknown" Display

**Files:**
- Modify: `OlasApp/Views/Profile/ProfileView.swift`

**Step 1: Add loading state**

Add to ProfileView state:
```swift
@State private var isLoadingProfile = true
```

**Step 2: Update the name display**

Replace the name Text:
```swift
if isLoadingProfile {
    Text("Loading...")
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(.secondary)
} else if let name = profile?.name ?? profile?.displayName, !name.isEmpty {
    Text(name)
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(.primary)
} else {
    Text(String(pubkey.prefix(8)) + "...")
        .font(.system(size: 18, weight: .medium, design: .monospaced))
        .foregroundStyle(.secondary)
}
```

**Step 3: Update loadProfile to set loading state**

```swift
private func loadProfile() async {
    defer {
        Task { @MainActor in isLoadingProfile = false }
    }

    // Add timeout for loading
    let timeoutTask = Task {
        try await Task.sleep(for: .seconds(3))
        await MainActor.run { isLoadingProfile = false }
    }

    for await metadata in await ndk.profileManager.subscribe(for: pubkey, maxAge: 60) {
        timeoutTask.cancel()
        await MainActor.run {
            self.profile = metadata
            self.isLoadingProfile = false
        }
    }
}
```

**Step 4: Build to verify**

Run: `vibe-tools xcode build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add OlasApp/Views/Profile/ProfileView.swift
git commit -m "fix: show loading state and npub fallback instead of 'Unknown' in profile"
```

---

## Task 10: Delete Unused ProfileViewModel

**Files:**
- Delete: `OlasApp/ViewModels/ProfileViewModel.swift`

**Step 1: Remove the unused file**

```bash
rm OlasApp/ViewModels/ProfileViewModel.swift
```

**Step 2: Build to verify no references**

Run: `vibe-tools xcode build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove unused ProfileViewModel"
```

---

## Task 11: Build and Test Full Flow

**Step 1: Build the app**

Run: `vibe-tools xcode build`
Expected: Build succeeds

**Step 2: Run on simulator and validate**

Using XcodeBuildMCP:
1. Boot simulator
2. Build and run
3. Log out if needed
4. Create new account
5. Verify profile setup view appears
6. Enter name, continue
7. Verify follow pack discovery loads
8. Select packs and follow
9. Verify lands on main feed
10. Go to Profile tab
11. Verify name shows (not "Unknown")

**Step 3: Final commit if any fixes needed**

---

## Summary

This plan implements:
1. **Kind 39089/39092 support** - Added constants and FollowPack model
2. **Modern onboarding flow** - Profile setup + follow pack discovery
3. **Profile fix** - Loading state and npub fallback instead of "Unknown"
4. **Clean code** - Removed dead ProfileViewModel

The onboarding guides users through:
1. Setting their display name (publishes kind:0)
2. Discovering and selecting follow packs
3. Following all selected accounts (publishes kind:3 contact list)
