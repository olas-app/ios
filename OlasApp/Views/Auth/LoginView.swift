import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

public struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: LoginMethod = .nsec
    @State private var nsec = ""
    @State private var bunkerUri = ""
    @State private var showError = false
    @State private var errorMessage = ""

    enum LoginMethod: String, CaseIterable {
        case nsec = "Private Key"
        case bunker = "Remote Signer"
    }

    public init(authViewModel: AuthViewModel) {
        self.authViewModel = authViewModel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Tab selector
                Picker("Login Method", selection: $selectedTab) {
                    ForEach(LoginMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case .nsec:
                        nsecLoginView
                    case .bunker:
                        bunkerLoginView
                    }
                }

                Spacer()
            }
            .padding(.vertical, 24)
            .navigationTitle("Connect Account")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .alert("Login Failed", isPresented: $showError) {
                    Button("OK") {}
                } message: {
                    Text(errorMessage)
                }
        }
    }

    private var nsecLoginView: some View {
        VStack(spacing: 24) {
            Text("Enter your private key (nsec)")
                .font(.headline)

            SecureField("nsec1...", text: $nsec)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .padding(.horizontal, 24)
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif

            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(OlasTheme.Colors.accent)
                Text("Your key stays on device and is never sent anywhere")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            Button {
                Task {
                    do {
                        try await authViewModel.loginWithNsec(nsec)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            } label: {
                if authViewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text("Connect")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(OlasTheme.Colors.accent)
            .foregroundStyle(.white)
            .cornerRadius(12)
            .disabled(nsec.isEmpty || authViewModel.isLoading)
            .padding(.horizontal, 24)

            Button("Paste from clipboard") {
                pasteFromClipboard()
            }
            .font(.subheadline)
            .foregroundStyle(OlasTheme.Colors.accent)
        }
    }

    private var bunkerLoginView: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connect with Remote Signer")
                    .font(.headline)

                Text("Enter a bunker:// or nostrconnect:// URI from your remote signing app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            TextField("bunker:// or nostrconnect://", text: $bunkerUri, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .lineLimit(3 ... 6)
                .padding(.horizontal, 24)
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            #endif

            HStack {
                Image(systemName: "network")
                    .foregroundStyle(OlasTheme.Colors.accent)
                Text("Events are signed remotely via NIP-46")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            Button {
                Task {
                    do {
                        try await authViewModel.loginWithBunker(bunkerUri)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            } label: {
                if authViewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text("Connect to Remote Signer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(OlasTheme.Colors.accent)
            .foregroundStyle(.white)
            .cornerRadius(12)
            .disabled(bunkerUri.isEmpty || authViewModel.isLoading)
            .padding(.horizontal, 24)

            Button("Paste from clipboard") {
                pasteFromClipboardBunker()
            }
            .font(.subheadline)
            .foregroundStyle(OlasTheme.Colors.accent)
        }
    }

    private func pasteFromClipboard() {
        #if os(iOS)
            if let clipboardContent = UIPasteboard.general.string {
                nsec = clipboardContent
            }
        #elseif os(macOS)
            if let clipboardContent = NSPasteboard.general.string(forType: .string) {
                nsec = clipboardContent
            }
        #endif
    }

    private func pasteFromClipboardBunker() {
        #if os(iOS)
            if let clipboardContent = UIPasteboard.general.string {
                bunkerUri = clipboardContent
            }
        #elseif os(macOS)
            if let clipboardContent = NSPasteboard.general.string(forType: .string) {
                bunkerUri = clipboardContent
            }
        #endif
    }
}
