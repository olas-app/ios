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
                    Group {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(displayName.isEmpty ? "Skip for Now" : "Continue")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        displayName.isEmpty
                            ? Color(.systemGray5)
                            : OlasTheme.Colors.accent
                    )
                    .foregroundStyle(displayName.isEmpty ? Color.primary : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
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
