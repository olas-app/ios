import AVKit
import NDKSwiftCore
import SwiftUI

struct VideoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PublishingState.self) private var publishingState

    let videoURL: URL
    let videoMode: VideoCaptureView.VideoMode
    let ndk: NDK

    @State private var player: AVPlayer?
    @State private var caption = ""
    @State private var isPublishing = false
    @State private var publishingProgress = ""
    @State private var publishingPercent: Double = 0
    @State private var publishError: Error?
    @State private var showError = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Video player
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                }

                Spacer()

                // Caption input
                VStack(alignment: .leading, spacing: 12) {
                    Text("Caption")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                        .tracking(1)

                    TextField("Write a caption...", text: $caption, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .lineLimit(3...6)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.1))
                        )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                // Mode indicator
                HStack(spacing: 8) {
                    Image(systemName: videoMode == .vine ? "leaf.fill" : "film")
                        .font(.system(size: 14))
                        .foregroundStyle(videoMode.color)
                    Text(videoMode.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 20)

                // Publish button
                Button {
                    Task {
                        await publishVideo()
                    }
                } label: {
                    if isPublishing {
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text(publishingProgress)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.7))
                            ProgressView(value: publishingPercent)
                                .tint(videoMode.color)
                                .frame(width: 200)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } else {
                        Text("Publish")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(videoMode.color)
                            )
                    }
                }
                .disabled(isPublishing)
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
        }
        .navigationBarBackButtonHidden(isPublishing)
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .alert("Publishing Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(publishError?.localizedDescription ?? "Unknown error")
        }
    }

    private func setupPlayer() {
        let avPlayer = AVPlayer(url: videoURL)
        avPlayer.actionAtItemEnd = .none

        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            avPlayer.seek(to: .zero)
            avPlayer.play()
        }

        player = avPlayer
        avPlayer.play()
    }

    private func publishVideo() async {
        isPublishing = true
        publishingProgress = "Preparing..."
        publishingPercent = 0

        do {
            _ = try await VideoPublishingService.publish(
                ndk: ndk,
                videoURL: videoURL,
                caption: caption,
                videoMode: videoMode
            ) { progress, percent in
                publishingProgress = progress
                publishingPercent = percent
            }

            // Success - dismiss all the way back
            await MainActor.run {
                publishingState.didPublish = true
                dismiss()
            }
        } catch {
            await MainActor.run {
                isPublishing = false
                publishError = error
                showError = true
            }
        }
    }
}
