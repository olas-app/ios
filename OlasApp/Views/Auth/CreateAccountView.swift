import NDKSwiftCore
import SwiftUI

public struct CreateAccountView: View {
    var authManager: NDKAuthManager
    var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    public init(authManager: NDKAuthManager, settings: SettingsManager) {
        self.authManager = authManager
        self.settings = settings
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Welcome message
                VStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 60))
                        .foregroundStyle(OlasTheme.Colors.accent)

                    Text("Welcome to Olas")
                        .font(.title2.weight(.bold))

                    Text("We'll create a new Nostr identity for you. Your private key will be stored securely on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Info box
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(OlasTheme.Colors.accent)
                        Text("A unique cryptographic key pair will be generated")
                            .font(.caption)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(OlasTheme.Colors.accent)
                        Text("Your private key never leaves your device")
                            .font(.caption)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(OlasTheme.Colors.accent)
                        Text("You can use this identity across all Nostr apps")
                            .font(.caption)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)

                // Create button
                Button {
                    Task {
                        await createAccount()
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Create My Account")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(
                    LinearGradient(
                        colors: [OlasTheme.Colors.accent, OlasTheme.Colors.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .cornerRadius(12)
                .disabled(isLoading)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .navigationTitle("Create Account")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .alert("Error", isPresented: $showError) {
                    Button("OK") {}
                } message: {
                    Text(errorMessage)
                }
        }
    }

    private func createAccount() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let signer = try NDKPrivateKeySigner.generate()
            _ = try await authManager.addSession(signer)
            settings.isNewAccount = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
