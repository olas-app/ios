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
