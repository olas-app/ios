import NDKSwiftCore
import SwiftUI

public struct OnboardingView: View {
    var authManager: NDKAuthManager
    var ndk: NDK
    var settings: SettingsManager
    @State private var showLogin = false
    @State private var animateBlobs = false
    @State private var logoGlow = false
    @State private var showError = false
    @State private var errorMessage = ""

    public init(authManager: NDKAuthManager, ndk: NDK, settings: SettingsManager) {
        self.authManager = authManager
        self.ndk = ndk
        self.settings = settings
    }

    public var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Aurora blobs
            AuroraBackground(animate: animateBlobs)

            // Content
            VStack(spacing: 0) {
                Spacer()

                // Logo
                OlasWaveLogo()
                    .frame(width: 110, height: 66)
                    .shadow(color: .white.opacity(logoGlow ? 0.6 : 0.4), radius: logoGlow ? 60 : 40)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: logoGlow)

                Text("Olas")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.white)
                    .tracking(-2)
                    .shadow(color: .white.opacity(0.3), radius: 60)
                    .padding(.top, 20)

                Text("Make waves.")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.8))
                    .tracking(1)
                    .padding(.top, 12)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        Task { await createAccount() }
                    } label: {
                        Text("Create Account")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(.white)
                            .foregroundStyle(Color(red: 0.23, green: 0.05, blue: 0.64)) // Deep purple
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .white.opacity(0.25), radius: 40, y: 10)
                    }

                    Button {
                        showLogin = true
                    } label: {
                        Text("I have a Nostr account")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(.white.opacity(0.1))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            animateBlobs = true
            logoGlow = true
        }
        .sheet(isPresented: $showLogin) {
            LoginView(authManager: authManager, ndk: ndk)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func createAccount() async {
        do {
            let signer = try NDKPrivateKeySigner.generate()
            _ = try await authManager.addSession(signer)
            settings.isNewAccount = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Aurora Background

private struct AuroraBackground: View {
    let animate: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Blob 1 - Teal (top-left)
                AuroraBlob(
                    colors: [Color(hex: "00f5d4"), Color(hex: "00bcd4")],
                    size: 280
                )
                .offset(x: -geometry.size.width / 2 + 80, y: -geometry.size.height / 2 + 60)

                // Blob 2 - Purple (top-right)
                AuroraBlob(
                    colors: [Color(hex: "7b2cbf"), Color(hex: "9d4edd")],
                    size: 250
                )
                .offset(x: geometry.size.width / 2 - 40, y: -geometry.size.height / 2 + 180)

                // Blob 3 - Pink (middle-left)
                AuroraBlob(
                    colors: [Color(hex: "f72585"), Color(hex: "ff006e")],
                    size: 220
                )
                .offset(x: -geometry.size.width / 2 + 60, y: 0)

                // Blob 4 - Blue (middle-right)
                AuroraBlob(
                    colors: [Color(hex: "4361ee"), Color(hex: "4cc9f0")],
                    size: 260
                )
                .offset(x: geometry.size.width / 2 - 50, y: geometry.size.height / 4)

                // Blob 5 - Deep Purple (bottom-left)
                AuroraBlob(
                    colors: [Color(hex: "3a0ca3"), Color(hex: "7209b7")],
                    size: 300
                )
                .offset(x: -geometry.size.width / 4, y: geometry.size.height / 2 - 60)

                // Blob 6 - Yellow/Orange (center)
                AuroraBlob(
                    colors: [Color(hex: "f9c74f"), Color(hex: "f8961e")],
                    size: 180,
                    baseOpacity: 0.5
                )
                .offset(x: 0, y: -geometry.size.height / 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .blur(radius: 60)
        .ignoresSafeArea()
    }
}

private struct AuroraBlob: View {
    let colors: [Color]
    let size: CGFloat
    var baseOpacity: Double = 0.7

    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .opacity(baseOpacity)
            .offset(
                x: isAnimating ? 30 : -30,
                y: isAnimating ? 40 : -40
            )
            .scaleEffect(isAnimating ? 1.15 : 0.95)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: Double.random(in: 6...10))
                    .repeatForever(autoreverses: true)
                ) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Olas Wave Logo (White)

private struct OlasWaveLogo: View {
    var body: some View {
        Canvas { context, size in
            let strokeWidth: CGFloat = 8
            let width = size.width
            let height = size.height

            // Calculate wave positions
            let wave1Start = CGPoint(x: width * 0.2, y: height * 0.58)
            let wave1Peak = CGPoint(x: width * 0.35, y: height * 0.33)
            let wave1End = CGPoint(x: width * 0.5, y: height * 0.58)

            let wave2Start = CGPoint(x: width * 0.35, y: height * 0.58)
            let wave2Peak = CGPoint(x: width * 0.5, y: height * 0.33)
            let wave2End = CGPoint(x: width * 0.65, y: height * 0.58)

            let wave3Start = CGPoint(x: width * 0.5, y: height * 0.58)
            let wave3Peak = CGPoint(x: width * 0.65, y: height * 0.33)
            let wave3End = CGPoint(x: width * 0.8, y: height * 0.58)

            // Wave 1 (full opacity)
            var path1 = Path()
            path1.move(to: wave1Start)
            path1.addLine(to: wave1Peak)
            path1.addLine(to: wave1End)
            context.stroke(
                path1,
                with: .color(.white),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
            )

            // Wave 2 (75% opacity)
            var path2 = Path()
            path2.move(to: wave2Start)
            path2.addLine(to: wave2Peak)
            path2.addLine(to: wave2End)
            context.stroke(
                path2,
                with: .color(.white.opacity(0.75)),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
            )

            // Wave 3 (50% opacity)
            var path3 = Path()
            path3.move(to: wave3Start)
            path3.addLine(to: wave3Peak)
            path3.addLine(to: wave3End)
            context.stroke(
                path3,
                with: .color(.white.opacity(0.5)),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

