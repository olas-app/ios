import SwiftUI
import NDKSwiftCore

struct LikeAnimation: View {
    @Binding var isAnimating: Bool

    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 0

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 80, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            .scaleEffect(scale)
            .opacity(opacity)
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    animate()
                }
            }
    }

    private func animate() {
        // Initial burst
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0)) {
            scale = 1.3
            opacity = 1
        }

        // Settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                scale = 1.0
            }
        }

        // Fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                opacity = 0
                scale = 1.2
            }
        }

        // Reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            scale = 0
            isAnimating = false
        }
    }
}

struct HeartButtonStyle: ButtonStyle {
    let isLiked: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

struct LikeButton: View {
    let event: NDKEvent
    @Environment(\.ndk) private var ndk

    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var animateHeart = false

    var body: some View {
        Button {
            Task { await toggleLike() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isLiked ? OlasTheme.Colors.heartRed : .primary)
                    .scaleEffect(animateHeart ? 1.2 : 1.0)

                if likeCount > 0 {
                    Text("\(likeCount)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(HeartButtonStyle(isLiked: isLiked))
        .onChange(of: animateHeart) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                        animateHeart = false
                    }
                }
            }
        }
        .task {
            await loadReactionCount()
        }
    }

    private func toggleLike() async {
        triggerHaptic()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            isLiked.toggle()
            if isLiked {
                animateHeart = true
                likeCount += 1
            } else {
                likeCount = max(0, likeCount - 1)
            }
        }

        if isLiked {
            await publishReaction()
        }
    }

    private func publishReaction() async {
        guard let ndk else { return }

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

    private func loadReactionCount() async {
        guard let ndk,
              let currentUserPubkey = await ndk.activeUser?.pubkey else {
            return
        }

        let reactionFilter = NDKFilter(
            kinds: [OlasConstants.EventKinds.reaction],
            events: [event.id],
            limit: 500
        )

        let subscription = ndk.subscribe(filter: reactionFilter)

        for await reactionEvent in subscription.events {
            guard !Task.isCancelled else { break }

            if reactionEvent.content == "+" {
                likeCount += 1

                // Check if this is the current user's reaction
                if reactionEvent.pubkey == currentUserPubkey {
                    isLiked = true
                }
            }
        }
    }

    private func triggerHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
}

struct CommentButton: View {
    let event: NDKEvent
    @Environment(\.ndk) private var ndk

    @State private var commentCount = 0
    @State private var showComments = false

    var body: some View {
        Button {
            showComments = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.right")
                    .font(.system(size: 20, weight: .medium))

                if commentCount > 0 {
                    Text("\(commentCount)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .sheet(isPresented: $showComments) {
            if let ndk {
                CommentsSheet(event: event, ndk: ndk)
            }
        }
        .task {
            await loadCommentCount()
        }
    }

    private func loadCommentCount() async {
        guard let ndk else { return }

        let commentFilter = NDKFilter(
            kinds: [OlasConstants.EventKinds.comment],
            events: [event.id],
            limit: 100
        )

        let commentSub = ndk.subscribe(filter: commentFilter)

        for await commentEvent in commentSub.events {
            guard !Task.isCancelled else { break }
            commentCount += 1
        }
    }
}

struct ZapButton: View {
    let event: NDKEvent
    let ndk: NDK
    @EnvironmentObject private var walletViewModel: WalletViewModel

    @State private var isAnimating = false
    @State private var showZapSheet = false
    @State private var selectedAmount: Int64 = 21
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var zapError: Error?
    @State private var totalZapAmount: Int64 = 0

    private let zapAmounts: [Int64] = [21, 100, 500, 1000]

    var body: some View {
        Button {
            triggerHaptic()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isAnimating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAnimating = false
            }

            if walletViewModel.isSetup && walletViewModel.balance > 0 {
                showZapSheet = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(OlasTheme.Colors.zapGold)
                    .scaleEffect(isAnimating ? 1.3 : 1.0)
                    .rotationEffect(.degrees(isAnimating ? 10 : 0))

                if totalZapAmount > 0 {
                    Text(formatSats(Int(totalZapAmount)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!walletViewModel.isSetup || walletViewModel.balance == 0)
        .opacity(walletViewModel.isSetup && walletViewModel.balance > 0 ? 1.0 : 0.5)
        .sheet(isPresented: $showZapSheet) {
            zapSheet
        }
        .task {
            await loadZapTotal()
        }
    }

    private var zapSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if showSuccess {
                    // Success view
                    VStack(spacing: 16) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(OlasTheme.Colors.zapGold)

                        Text("Zap Sent!")
                            .font(.title2.bold())

                        Text("\(selectedAmount) sats")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    Spacer()

                    Button {
                        showZapSheet = false
                        showSuccess = false
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OlasTheme.Colors.accent)
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                } else {
                    // Amount selection
                    VStack(spacing: 8) {
                        Text("Send Zap")
                            .font(.headline)

                        Text("Balance: \(walletViewModel.balance) sats")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top)

                    // Amount buttons
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(zapAmounts, id: \.self) { amount in
                            Button {
                                selectedAmount = amount
                            } label: {
                                VStack(spacing: 4) {
                                    Text("\(amount)")
                                        .font(.title2.bold())

                                    Text("sats")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedAmount == amount
                                              ? OlasTheme.Colors.zapGold
                                              : Color.secondary.opacity(0.1))
                                )
                                .foregroundStyle(selectedAmount == amount ? .white : .primary)
                            }
                            .disabled(amount > walletViewModel.balance)
                            .opacity(amount > walletViewModel.balance ? 0.5 : 1.0)
                        }
                    }
                    .padding(.horizontal)

                    Spacer()

                    // Send button
                    Button {
                        Task { await sendZap() }
                    } label: {
                        if isSending {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        } else {
                            HStack {
                                Image(systemName: "bolt.fill")
                                Text("Zap \(selectedAmount) sats")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OlasTheme.Colors.zapGold)
                    .disabled(isSending || selectedAmount > walletViewModel.balance)
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showZapSheet = false
                    }
                }
            }
            .alert("Zap Failed", isPresented: .init(
                get: { zapError != nil },
                set: { if !$0 { zapError = nil } }
            )) {
                Button("OK") { zapError = nil }
            } message: {
                Text(zapError?.localizedDescription ?? "Unknown error")
            }
        }
        .presentationDetents([.medium])
    }

    private func sendZap() async {
        isSending = true
        defer { isSending = false }

        do {
            try await walletViewModel.zap(
                event: event,
                amount: selectedAmount
            )

            // Update total
            totalZapAmount += selectedAmount

            // Show success
            withAnimation {
                showSuccess = true
            }

            // Haptic
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)

        } catch {
            zapError = error

            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.error)
        }
    }

    private func loadZapTotal() async {
        // Subscribe to zaps for this event
        var total: Int64 = 0

        do {
            for try await zapInfo in ndk.zapManager.subscribeToZaps(for: event) {
                total += zapInfo.amountSats

                await MainActor.run {
                    totalZapAmount = total
                }

                // Limit how many we count
                if total > 1_000_000 { break }
            }
        } catch {
            // Silently ignore errors loading zap totals
        }
    }

    private func formatSats(_ amount: Int) -> String {
        if amount >= 1000000 {
            return String(format: "%.1fM", Double(amount) / 1000000)
        } else if amount >= 1000 {
            return String(format: "%.1fK", Double(amount) / 1000)
        }
        return "\(amount)"
    }

    private func triggerHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}

struct ShareButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "paperplane")
                .font(.system(size: 20, weight: .medium))
        }
        .foregroundStyle(.primary)
    }
}
