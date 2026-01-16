import SwiftUI

struct PublishingBannerOverlay: View {
    @Bindable var publishingState: PublishingState

    var body: some View {
        if publishingState.isPublishing || publishingState.error != nil {
            bannerContent
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect()
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: publishingState.isPublishing)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: publishingState.error != nil)
        }
    }

    @ViewBuilder
    private var bannerContent: some View {
        VStack(spacing: 8) {
            statusRow
            if publishingState.error == nil {
                progressBar
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 12) {
            statusIcon
            Text(publishingState.publishingStatus)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            if publishingState.error != nil {
                dismissButton
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if publishingState.error != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.tint)
        }
    }

    @ViewBuilder
    private var dismissButton: some View {
        Button {
            publishingState.dismissError()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.2))
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * publishingState.publishingProgress, height: 4)
                    .animation(.easeOut(duration: 0.2), value: publishingState.publishingProgress)
            }
        }
        .frame(height: 4)
    }
}
