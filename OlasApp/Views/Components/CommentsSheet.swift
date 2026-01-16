import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

struct CommentsSheet: View {
    let event: NDKEvent
    let ndk: NDK
    @Environment(\.dismiss) private var dismiss
    @Environment(MuteListManager.self) private var muteListManager

    @State private var comments: [NDKEvent] = []
    @State private var newComment = ""
    @State private var isSending = false
    @State private var commentsTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    private var filteredComments: [NDKEvent] {
        comments.filter { !muteListManager.isMuted($0.pubkey) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Comments list - streams in as they arrive
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredComments, id: \.id) { comment in
                            CommentRow(comment: comment, ndk: ndk)
                        }
                    }
                }

                Divider()

                // Input bar
                commentInput
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                commentsTask = Task {
                    await loadComments()
                }
                await commentsTask?.value
            }
            .onDisappear {
                commentsTask?.cancel()
                commentsTask = nil
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(OlasTheme.Glass.cornerRadius)
    }

    private var commentInput: some View {
        HStack(spacing: 12) {
            TextField("Add a comment...", text: $newComment, axis: .vertical)
                .lineLimit(1 ... 4)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassBackground(level: .ultraThin, cornerRadius: OlasTheme.Glass.cornerRadius)
                .focused($isInputFocused)

            Button {
                Task { await sendComment() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        newComment.isEmpty ? .secondary : OlasTheme.Colors.accent
                    )
            }
            .disabled(newComment.isEmpty || isSending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func loadComments() async {
        let filter = NDKFilter.tagging(event, kinds: [OlasConstants.EventKinds.comment], limit: 100)

        let subscription = ndk.subscribe(filter: filter)

        // Stream comments as they arrive (events now come in batches)
        for await commentEvents in subscription.events {
            guard !Task.isCancelled else { break }

            for commentEvent in commentEvents {
                // Insert in sorted position (oldest first for comments)
                let insertIndex = comments.firstIndex { commentEvent.createdAt < $0.createdAt } ?? comments.endIndex
                comments.insert(commentEvent, at: insertIndex)
            }
        }
    }

    private func sendComment() async {
        guard !newComment.isEmpty else { return }

        isSending = true
        let commentText = newComment
        newComment = ""

        do {
            let replyEvent = try await NDKEventBuilder.reply(to: event, ndk: ndk)
                .content(commentText)
                .build()
            _ = try await ndk.publish(replyEvent)
            let newEvent = replyEvent

            // Add to local list
            await MainActor.run {
                comments.append(newEvent)
                triggerHaptic()
            }
        } catch {
            // Restore comment text on error
            newComment = commentText
        }

        isSending = false
    }

    private func triggerHaptic() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
    }
}

struct CommentRow: View {
    let comment: NDKEvent
    let ndk: NDK

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NDKUIProfilePicture(ndk: ndk, pubkey: comment.pubkey, size: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(ndk.profile(for: comment.pubkey).displayName)
                        .font(.subheadline.weight(.semibold))

                    NDKUIRelativeTime(timestamp: comment.createdAt)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(comment.content)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                // Like button for comment
                Button {
                    // Like comment
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                            .font(.caption)
                        Text("Like")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
