import AVKit
import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

struct VideoFeedItem: View {
    let event: NDKEvent
    let ndk: NDK
    let isVisible: Bool

    @State private var player: AVPlayer?
    @State private var isMuted = false
    @State private var showLikeAnimation = false
    @State private var showCommentsSheet = false
    @State private var loopObserver: NSObjectProtocol?
    @State private var blurhashImage: UIImage?

    @Environment(MuteListManager.self) private var muteListManager

    private var video: NDKVideo {
        NDKVideo(event: event)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                // Video or thumbnail
                videoContent
                    .frame(width: geometry.size.width, height: geometry.size.height)

                // Like animation
                LikeAnimation(isAnimating: $showLikeAnimation)

                // Overlays
                VStack {
                    Spacer()
                    bottomOverlay
                }

                // Right side actions
                VStack {
                    Spacer()
                    rightSideActions
                        .padding(.bottom, 100)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            handleDoubleTap()
        }
        .onTapGesture(count: 1) {
            toggleMute()
        }
        .task {
            decodeBlurhash()
            if isVisible {
                setupPlayer()
            }
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                setupPlayer()
            } else {
                cleanupPlayer()
            }
        }
        .onDisappear {
            cleanupPlayer()
        }
        .sheet(isPresented: $showCommentsSheet) {
            CommentsSheet(event: event, ndk: ndk)
        }
    }

    // MARK: - Video Content

    @ViewBuilder
    private var videoContent: some View {
        if let player {
            VideoPlayer(player: player)
                .disabled(true)
                .aspectRatio(video.primaryAspectRatio ?? (9.0 / 16.0), contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    muteIndicator
                }
        } else {
            thumbnailView
        }
    }

    private var thumbnailView: some View {
        Group {
            if let thumbnailURLString = video.thumbnailURL,
               let thumbnailURL = URL(string: thumbnailURLString)
            {
                CachedAsyncImage(
                    url: thumbnailURL,
                    blurhash: video.primaryBlurhash,
                    aspectRatio: video.primaryAspectRatio,
                    contentMode: .fit
                ) {
                    blurhashPlaceholder
                }
            } else {
                blurhashPlaceholder
            }
        }
        .overlay {
            ProgressView()
                .tint(.white)
        }
    }

    @ViewBuilder
    private var blurhashPlaceholder: some View {
        if let blurhashImage {
            Image(uiImage: blurhashImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
        }
    }

    private var muteIndicator: some View {
        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .font(.caption)
            .padding(8)
            .glassEffect()
            .padding()
    }

    // MARK: - Bottom Overlay

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author info
            HStack(spacing: 12) {
                NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 44)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(ndk.profile(for: event.pubkey).displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    NDKUIRelativeTime(timestamp: event.createdAt)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()
            }

            // Caption/content
            if !event.content.isEmpty {
                Text(event.content)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(3)
            }

            // Duration badge
            if let duration = video.duration {
                Text(formatDuration(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .padding(.trailing, 60) // Make room for right side actions
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Right Side Actions

    private var rightSideActions: some View {
        VStack(spacing: 20) {
            // Like
            LikeButton(event: event)
                .foregroundStyle(.white)
                .labelStyle(.iconOnly)
                .font(.title2)

            // Comment
            Button {
                showCommentsSheet = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                        .font(.title2)
                    Text("Comments")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
            }

            // Zap
            ZapButton(event: event, ndk: ndk)
                .foregroundStyle(.white)
                .labelStyle(.iconOnly)
                .font(.title2)

            // Share
            ShareButton {
                shareVideo()
            }
            .foregroundStyle(.white)
            .font(.title2)
        }
    }

    // MARK: - Actions

    private func setupPlayer() {
        guard player == nil,
              let videoURLString = video.primaryVideoURL,
              let videoURL = URL(string: videoURLString) else { return }

        let playerItem = AVPlayerItem(url: videoURL)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.isMuted = isMuted
        player = avPlayer

        // Loop video
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak avPlayer] _ in
            avPlayer?.seek(to: .zero)
            avPlayer?.play()
        }

        avPlayer.play()
    }

    private func cleanupPlayer() {
        player?.pause()
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        player = nil
    }

    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted

        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    private func handleDoubleTap() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        showLikeAnimation = true

        Task {
            _ = try? await ndk.react(to: event, with: "+")
        }
    }

    private func shareVideo() {
        guard let nevent = try? Bech32.nevent(eventId: event.id, author: event.pubkey, kind: event.kind) else {
            return
        }
        let url = "https://njump.me/\(nevent)"
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController
        {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func decodeBlurhash() {
        guard blurhashImage == nil,
              let blurhash = video.primaryBlurhash,
              !blurhash.isEmpty else { return }

        let aspectRatio = video.primaryAspectRatio ?? (9.0 / 16.0)
        let size: CGSize
        if aspectRatio > 1 {
            size = CGSize(width: 32, height: 32 / aspectRatio)
        } else {
            size = CGSize(width: 32 * aspectRatio, height: 32)
        }

        blurhashImage = BlurhashDecoder.decode(blurhash, size: size)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
