import NDKSwiftCore
import SwiftUI

struct NIP46LoginView: View {
    @StateObject private var viewModel: NIP46ViewModel
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var showError = false
    @State private var errorMessage = ""

    init(authViewModel: AuthViewModel, ndk: NDK?) {
        self.authViewModel = authViewModel
        _viewModel = StateObject(wrappedValue: NIP46ViewModel(ndk: ndk))
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Scan with Remote Signer")
                .font(.headline)

            if let qrCode = viewModel.qrCode {
                VStack(spacing: 16) {
                    Image(uiImage: qrCode)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 300, height: 300)
                        .onTapGesture {
                            if let urlString = viewModel.nostrConnectURL, let url = URL(string: urlString) {
                                openURL(url)
                            }
                        }

                    Text("Tap QR code to open in signer app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: "qrcode")
                        .foregroundStyle(OlasTheme.Colors.accent)
                    Text("Scan this QR code with your remote signer app (e.g., Amber, nsec.app)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                // Wait for connection button
                Button {
                    Task {
                        do {
                            let (bunkerSigner, pubkey) = try await viewModel.waitForConnection()
                            // Once connected, update the AuthViewModel
                            try await authViewModel.loginWithNIP46(bunkerSigner: bunkerSigner, pubkey: pubkey)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                } label: {
                    if viewModel.isWaitingForConnection || authViewModel.isLoading {
                        HStack {
                            ProgressView()
                            Text("Waiting for remote signer...")
                        }
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
                .disabled(viewModel.isWaitingForConnection || authViewModel.isLoading)
                .padding(.horizontal, 24)

            } else {
                ProgressView("Generating QR Code...")
                    .padding(.vertical, 100)
            }

            Spacer()
        }
        .padding(.vertical, 24)
        .onAppear {
            Task {
                await viewModel.generateNostrConnectURL()
            }
        }
        .alert("Connection Failed", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .navigationTitle("NIP-46 Login")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
