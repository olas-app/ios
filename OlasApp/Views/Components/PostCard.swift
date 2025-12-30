// PostCard.swift
import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

public struct PostCard: View, Equatable {
    let event: NDKEvent
    let ndk: NDK
    let onProfileTap: ((String) -> Void)?

    @State private var showLikeAnimation = false
    @State private var showFullscreenImage = false
    @State private var showReportSheet = false

    @Environment(MuteListManager.self) private var muteListManager

    public init(event: NDKEvent, ndk: NDK, onProfileTap: ((String) -> Void)? = nil) {
        self.event = event
        self.ndk = ndk
        self.onProfileTap = onProfileTap
    }

    public static func == (lhs: PostCard, rhs: PostCard) -> Bool {
        // Only compare event IDs to prevent unnecessary rerenders
        lhs.event.id == rhs.event.id
    }

    private var image: NDKImage {
        NDKImage(event: event)
    }

    private var isVideo: Bool {
        event.kind == OlasConstants.EventKinds.shortVideo
    }

    public var body: some View {
        if isVideo {
            VideoPostCard(event: event, ndk: ndk, onProfileTap: onProfileTap)
        } else {
            imagePostContent
        }
    }

    private var imagePostContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            postHeader
            postImage
            postActions
            postCaption
        }
        .accessibilityIdentifier("post_card")
        .fullScreenCover(isPresented: $showFullscreenImage) {
            if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                FullscreenImageViewer(
                    url: url,
                    blurhash: image.primaryBlurhash,
                    aspectRatio: image.primaryAspectRatio,
                    isPresented: $showFullscreenImage
                )
            }
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheet(event: event, ndk: ndk)
        }
    }

    private var postHeader: some View {
        HStack(spacing: 12) {
            profilePictureButton

            VStack(alignment: .leading, spacing: 2) {
                Button {
                    onProfileTap?(event.pubkey)
                } label: {
                    Text(ndk.profile(for: event.pubkey).displayName)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("post_author_name")

                NDKUIRelativeTime(timestamp: event.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button {
                    copyEventId()
                } label: {
                    Label("Copy ID", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    showReportSheet = true
                } label: {
                    Label("Report", systemImage: "exclamationmark.triangle")
                }

                Button(role: .destructive) {
                    Task { await muteAuthor() }
                } label: {
                    Label("Mute Author", systemImage: "speaker.slash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityIdentifier("post_author_header")
    }

    private var profilePictureButton: some View {
        Button {
            onProfileTap?(event.pubkey)
        } label: {
            NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 40)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("post_author_avatar")
    }

    private var postImage: some View {
        GeometryReader { geometry in
            let maxHeight = geometry.size.width * 1.25 // Max aspect ratio of 4:5 (portrait)

            ZStack {
                Group {
                    if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                        CachedAsyncImage(
                            url: url,
                            blurhash: image.primaryBlurhash,
                            aspectRatio: image.primaryAspectRatio,
                            contentMode: .fill
                        ) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .overlay(
                                    ProgressView()
                                        .tint(OlasTheme.Colors.accent)
                                )
                        }
                        .accessibilityLabel(image.primaryAlt ?? "Post image")
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            )
                            .accessibilityLabel("Image not available")
                    }
                }
                .frame(width: geometry.size.width, height: min(imageHeight(for: geometry.size.width), maxHeight))
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    handleDoubleTap()
                }
                .onTapGesture(count: 1) {
                    showFullscreenImage = true
                }

                // Like animation overlay
                LikeAnimation(isAnimating: $showLikeAnimation)
            }
        }
        .frame(height: imageDisplayHeight)
    }

    private func imageHeight(for width: CGFloat) -> CGFloat {
        if let aspectRatio = image.primaryAspectRatio, aspectRatio > 0 {
            return width / aspectRatio
        }
        return width // Square fallback
    }

    private var imageDisplayHeight: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let maxHeight = screenWidth * 1.25
        return min(imageHeight(for: screenWidth), maxHeight)
    }

    private var postActions: some View {
        HStack(spacing: 20) {
            LikeButton(event: event)

            CommentButton(event: event)

            ZapButton(event: event, ndk: ndk)

            Spacer()

            ShareButton {
                // Share action
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var postCaption: some View {
        Group {
            if !event.content.isEmpty {
                PostCaptionText(ndk: ndk, pubkey: event.pubkey, content: event.content)
                    .lineLimit(3)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    private func handleDoubleTap() {
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Show animation
        showLikeAnimation = true

        // Publish reaction - LikeButton will pick it up via subscription
        Task {
            try? await ndk.publish { builder in
                builder
                    .kind(OlasConstants.EventKinds.reaction)
                    .content("+")
                    .tag(["e", event.id])
                    .tag(["p", event.pubkey])
                    .tag(["k", "\(event.kind)"])
            }
        }
    }

    private func muteAuthor() async {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        do {
            try await muteListManager.mute(event.pubkey)
        } catch {
            // Mute failed silently - user can retry
        }
    }

    private func copyEventId() {
        guard let nevent = try? Bech32.nevent(eventId: event.id, author: event.pubkey, kind: event.kind) else {
            return
        }
        UIPasteboard.general.string = nevent

        let impact = UINotificationFeedbackGenerator()
        impact.notificationOccurred(.success)
    }
}

// MARK: - PostCaptionText

/// A component that displays username and caption as flowing inline text
private struct PostCaptionText: View {
    let ndk: NDK
    let pubkey: String
    let content: String

    var body: some View {
        let profile = ndk.profile(for: pubkey)

        (Text(profile.displayName).fontWeight(.semibold) + Text(" ") + Text(content))
            .font(.subheadline)
    }
}

// MARK: - FullscreenImageViewer

struct FullscreenImageViewer: View {
    let url: URL
    let blurhash: String?
    let aspectRatio: CGFloat?
    @Binding var isPresented: Bool

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var blurhashImage: UIImage?
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.ignoresSafeArea()

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
                    .scaleEffect(scale)
                    .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 1), 5)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                if scale < 1.0 {
                                    withAnimation(.spring()) {
                                        scale = 1.0
                                        offset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .updating($dragOffset) { value, state, _ in
                                if scale > 1 {
                                    state = value.translation
                                }
                            }
                            .onEnded { value in
                                if scale > 1 {
                                    offset.width += value.translation.width
                                    offset.height += value.translation.height
                                } else if abs(value.translation.height) > 100 {
                                    isPresented = false
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if scale > 1 {
                                scale = 1.0
                                offset = .zero
                            } else {
                                scale = 2.5
                            }
                        }
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
            }
        }
        .statusBarHidden()
        .onAppear {
            decodeBlurhash()
        }
    }

    private func decodeBlurhash() {
        guard blurhashImage == nil, let blurhash, !blurhash.isEmpty else { return }

        let size: CGSize
        if let aspectRatio, aspectRatio > 0 {
            if aspectRatio > 1 {
                size = CGSize(width: 32, height: 32 / aspectRatio)
            } else {
                size = CGSize(width: 32 * aspectRatio, height: 32)
            }
        } else {
            size = CGSize(width: 32, height: 32)
        }

        blurhashImage = BlurhashDecoder.decode(blurhash, size: size)
    }
}
