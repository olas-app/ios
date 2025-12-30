import AVKit
import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

struct FullscreenPostViewer: View {
    let event: NDKEvent
    let ndk: NDK
    @Binding var isPresented: Bool
    let namespace: Namespace.ID

    @State private var player: AVPlayer?
    @State private var isMuted = false
    @State private var isLiked = false
    @State private var showLikeAnimation = false
    @State private var likeCount = 0
    @State private var dragOffset: CGFloat = 0
    @State private var loopObserver: NSObjectProtocol?
    @State private var reactionsTask: Task<Void, Never>?

    private var isVideo: Bool {
        event.kind == OlasConstants.EventKinds.shortVideo
    }

    private var image: NDKImage {
        NDKImage(event: event)
    }

    private var video: NDKVideo {
        NDKVideo(event: event)
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.ignoresSafeArea()

                if isVideo {
                    videoContent
                } else {
                    imageContent
                }

                // Overlay UI
                VStack {
                    // Top bar with close button
                    HStack {
                        Spacer()
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding()
                    }

                    Spacer()

                    // Bottom info overlay
                    bottomOverlay
                }

                // Like animation
                LikeAnimation(isAnimating: $showLikeAnimation)
            }
            .offset(y: dragOffset)
            .gesture(
                // Dismiss gesture - only works when not zoomed
                DragGesture()
                    .onChanged { value in
                        // Only allow dismiss drag when not zoomed
                        guard !isZoomed else { return }
                        if abs(value.translation.height) > abs(value.translation.width) {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        guard !isZoomed else { return }
                        if abs(value.translation.height) > 100 {
                            isPresented = false
                        } else {
                            withAnimation(.spring(response: 0.3)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .statusBarHidden()
        .task {
            if isVideo {
                setupPlayer()
            }
            loadReactions()
        }
        .onDisappear {
            cleanupPlayer()
            reactionsTask?.cancel()
            reactionsTask = nil
        }
    }

    // MARK: - Video Content

    private var videoContent: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .aspectRatio(video.primaryAspectRatio ?? (9.0 / 16.0), contentMode: .fit)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            handleDoubleTap()
        }
        .onTapGesture(count: 1) {
            toggleMute()
        }
        .overlay(alignment: .bottomLeading) {
            // Mute indicator
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.5))
                .clipShape(Circle())
                .padding()
        }
    }

    // MARK: - Image Content

    @State private var imageScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var zoomAnchor: UnitPoint = .center
    @State private var blurhashImage: UIImage?

    private var isZoomed: Bool {
        imageScale > 1.01
    }

    private var imageContent: some View {
        GeometryReader { geometry in
            let imageView = Group {
                if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                    KFImage(url)
                        .placeholder {
                            if let blurhashImage {
                                Image(uiImage: blurhashImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .fade(duration: 0.2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .matchedGeometryEffect(id: "image-\(event.id)", in: namespace)
                        .onAppear {
                            decodeBlurhash()
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(imageScale, anchor: zoomAnchor)
            .offset(imageOffset)
            .gesture(
                // Pan gesture - only active when zoomed
                DragGesture()
                    .onChanged { value in
                        guard isZoomed else { return }
                        imageOffset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = imageOffset
                        constrainOffset(in: geometry.size)
                    }
            )
            .gesture(
                // Pinch-to-zoom with anchor point
                MagnifyGesture()
                    .onChanged { value in
                        // Calculate anchor from gesture start location
                        let anchor = UnitPoint(
                            x: value.startAnchor.x,
                            y: value.startAnchor.y
                        )
                        zoomAnchor = anchor

                        let delta = value.magnification / lastScale
                        lastScale = value.magnification
                        let newScale = imageScale * delta
                        imageScale = min(max(newScale, 1), 5)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                        if imageScale <= 1.0 {
                            withAnimation(.spring(response: 0.3)) {
                                imageScale = 1.0
                                imageOffset = .zero
                                lastOffset = .zero
                                zoomAnchor = .center
                            }
                        } else {
                            constrainOffset(in: geometry.size)
                        }
                    }
            )
            .onTapGesture(count: 2) { location in
                if isZoomed {
                    // Zoom out
                    withAnimation(.spring(response: 0.3)) {
                        imageScale = 1.0
                        imageOffset = .zero
                        lastOffset = .zero
                        zoomAnchor = .center
                    }
                } else {
                    // Zoom in at tap location
                    let anchor = UnitPoint(
                        x: location.x / geometry.size.width,
                        y: location.y / geometry.size.height
                    )
                    zoomAnchor = anchor
                    withAnimation(.spring(response: 0.3)) {
                        imageScale = 2.5
                    }
                    handleDoubleTap()
                }
            }

            imageView
        }
    }

    private func constrainOffset(in size: CGSize) {
        // Calculate max allowed offset based on zoom level
        let scaledWidth = size.width * imageScale
        let scaledHeight = size.height * imageScale
        let maxOffsetX = max(0, (scaledWidth - size.width) / 2)
        let maxOffsetY = max(0, (scaledHeight - size.height) / 2)

        withAnimation(.spring(response: 0.2)) {
            imageOffset = CGSize(
                width: min(max(imageOffset.width, -maxOffsetX), maxOffsetX),
                height: min(max(imageOffset.height, -maxOffsetY), maxOffsetY)
            )
            lastOffset = imageOffset
        }
    }

    private func decodeBlurhash() {
        guard blurhashImage == nil,
              let blurhash = image.primaryBlurhash,
              !blurhash.isEmpty else { return }

        let aspectRatio = image.primaryAspectRatio ?? 1.0
        let size: CGSize
        if aspectRatio > 1 {
            size = CGSize(width: 32, height: 32 / aspectRatio)
        } else {
            size = CGSize(width: 32 * aspectRatio, height: 32)
        }

        blurhashImage = BlurhashDecoder.decode(blurhash, size: size)
    }

    // MARK: - Bottom Overlay

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author info
            HStack(spacing: 12) {
                NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 40)
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

            // Caption
            if !event.content.isEmpty {
                Text(event.content)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(3)
            }

            // Actions
            HStack(spacing: 24) {
                Button {
                    Task {
                        if !isLiked {
                            handleDoubleTap()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? .red : .white)
                        if likeCount > 0 {
                            Text("\(likeCount)")
                                .foregroundStyle(.white)
                        }
                    }
                    .font(.title3)
                }

                ZapButton(event: event, ndk: ndk)
                    .foregroundStyle(.white)

                Spacer()

                ShareButton {}
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Actions

    private func setupPlayer() {
        guard let videoURLString = video.primaryVideoURL,
              let videoURL = URL(string: videoURLString) else { return }

        let playerItem = AVPlayerItem(url: videoURL)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.isMuted = false // Start with sound ON in fullscreen
        isMuted = false
        player = avPlayer

        // Loop video - store observer for cleanup
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
        guard !isLiked else { return }

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        showLikeAnimation = true

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isLiked = true
            likeCount += 1
        }

        Task { await publishReaction() }
    }

    private func publishReaction() async {
        do {
            _ = try await ndk.publish { builder in
                builder
                    .kind(OlasConstants.EventKinds.reaction)
                    .content("+")
                    .tag(["e", event.id])
                    .tag(["p", event.pubkey])
                    .tag(["k", "\(event.kind)"])
            }
        } catch {
            withAnimation {
                isLiked = false
                likeCount = max(0, likeCount - 1)
            }
        }
    }

    private func loadReactions() {
        reactionsTask?.cancel()
        reactionsTask = Task {
            let reactionFilter = NDKFilter(
                kinds: [OlasConstants.EventKinds.reaction],
                limit: 500
            )

            let subscription = ndk.subscribe(filter: reactionFilter)

            for await reactionEvents in subscription.events {
                if Task.isCancelled { break }
                for reactionEvent in reactionEvents {
                    let referencesOurEvent = reactionEvent.tags.contains { tag in
                        tag.first == "e" && tag.count > 1 && tag[1] == event.id
                    }

                    if referencesOurEvent && reactionEvent.content == "+" {
                        likeCount += 1
                    }
                }
            }
        }
    }
}
