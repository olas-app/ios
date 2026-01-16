import NDKSwiftCore
import NDKSwiftUI
import SwiftUI

struct LikeAnimation: View {
    @Binding var isAnimating: Bool

    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var animationTask: Task<Void, Never>?

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
            .onDisappear {
                animationTask?.cancel()
                animationTask = nil
            }
    }

    private func animate() {
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            // Initial burst
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0)) {
                scale = 1.3
                opacity = 1
            }

            // Settle
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                scale = 1.0
            }

            // Fade out
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                opacity = 0
                scale = 1.2
            }

            // Reset
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
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

    @State private var reactionState: ReactionState?
    @State private var animateHeart = false
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        Button {
            Task { await toggleLike() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: reactionState?.hasReacted == true ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(reactionState?.hasReacted == true ? OlasTheme.Colors.heartRed : .primary)
                    .scaleEffect(animateHeart ? 1.2 : 1.0)

                if let count = reactionState?.count, count > 0 {
                    Text("\(count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(HeartButtonStyle(isLiked: reactionState?.hasReacted ?? false))
        .onChange(of: animateHeart) { _, newValue in
            if newValue {
                animationTask?.cancel()
                animationTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                        animateHeart = false
                    }
                }
            }
        }
        .task {
            guard let ndk else { return }
            let state = ReactionStateCache.shared.state(for: event, ndk: ndk)
            reactionState = state
            await state.start()
        }
        .onDisappear {
            reactionState?.stop()
            animationTask?.cancel()
            animationTask = nil
        }
    }

    private func toggleLike() async {
        guard let reactionState else { return }

        triggerHaptic()

        // Animate the heart
        if !reactionState.hasReacted {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                animateHeart = true
            }
        }

        do {
            try await reactionState.toggle()
        } catch {
            // Toggle failed - state remains unchanged
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
    @State private var commentTask: Task<Void, Never>?

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
            commentTask = Task {
                await loadCommentCount()
            }
            await commentTask?.value
        }
        .onDisappear {
            commentTask?.cancel()
            commentTask = nil
        }
    }

    private func loadCommentCount() async {
        guard let ndk else { return }

        let commentFilter = NDKFilter.tagging(event, kinds: [OlasConstants.EventKinds.comment], limit: 100)

        let commentSub = ndk.subscribe(filter: commentFilter)

        for await commentEvents in commentSub.events {
            guard !Task.isCancelled else { break }
            commentCount += commentEvents.count
        }
    }
}

struct ZapButton: View {
    let event: NDKEvent
    let ndk: NDK
    @Environment(WalletViewModel.self) private var walletViewModel

    @State private var isAnimating = false
    @State private var showZapSheet = false
    @State private var selectedAmount: Int64 = 21
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var zapError: Error?
    @State private var totalZapAmount: Int64 = 0
    @State private var zapTask: Task<Void, Never>?
    @State private var animationTask: Task<Void, Never>?

    private let zapAmounts: [Int64] = [21, 100, 500, 1000]

    var body: some View {
        Button {
            triggerHaptic()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isAnimating = true
            }
            animationTask?.cancel()
            animationTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
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
            zapTask = Task {
                await loadZapTotal()
            }
            await zapTask?.value
        }
        .onDisappear {
            zapTask?.cancel()
            zapTask = nil
            animationTask?.cancel()
            animationTask = nil
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
                    .buttonStyle(.glassProminent)
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
                        GridItem(.flexible()),
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
                    .buttonStyle(.glassProminent)
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
            for try await zapInfo in ndk.zapManager.subscribeToZaps(for: event, pubkey: nil) {
                guard !Task.isCancelled else { break }
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
        if amount >= 1_000_000 {
            return String(format: "%.1fM", Double(amount) / 1_000_000)
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

struct RepostButton: View {
    let event: NDKEvent
    @Environment(\.ndk) private var ndk

    @State private var repostState: RepostState?
    @State private var showRepostMenu = false
    @State private var showQuoteComposer = false
    @State private var quoteContent = ""
    @State private var isAnimating = false
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        Button {
            triggerHaptic()
            showRepostMenu = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.2.squarepath")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(repostState?.hasReposted == true ? OlasTheme.Colors.repostGreen : .primary)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .rotationEffect(.degrees(isAnimating ? 15 : 0))

                if let count = repostState?.count, count > 0 {
                    Text("\(count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Repost", isPresented: $showRepostMenu) {
            Button {
                Task { await toggleRepost() }
            } label: {
                if repostState?.hasReposted == true {
                    Label("Undo Repost", systemImage: "arrow.uturn.backward")
                } else {
                    Label("Repost", systemImage: "arrow.2.squarepath")
                }
            }

            Button {
                showQuoteComposer = true
            } label: {
                Label("Quote", systemImage: "quote.bubble")
            }

            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showQuoteComposer) {
            quoteComposerSheet
        }
        .task {
            guard let ndk else { return }
            let state = RepostStateCache.shared.state(for: event, ndk: ndk)
            repostState = state
            await state.start()
        }
        .onDisappear {
            repostState?.stop()
            animationTask?.cancel()
            animationTask = nil
        }
    }

    private var quoteComposerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Original post preview
                VStack(alignment: .leading, spacing: 8) {
                    if let ndk {
                        HStack(spacing: 8) {
                            NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 24)
                                .clipShape(Circle())

                            Text(ndk.profile(for: event.pubkey).displayName)
                                .font(.subheadline.weight(.medium))

                            Spacer()
                        }
                    }

                    Text(event.content)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)

                // Quote input
                TextField("Add a comment...", text: $quoteContent, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding()
                    .lineLimit(5...10)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Quote Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showQuoteComposer = false
                        quoteContent = ""
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task { await postQuote() }
                    }
                    .disabled(quoteContent.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func toggleRepost() async {
        guard let repostState else { return }

        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            isAnimating = true
        }

        animationTask?.cancel()
        animationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            withAnimation {
                isAnimating = false
            }
        }

        do {
            try await repostState.toggle()

            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)
        } catch {
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.error)
        }
    }

    private func postQuote() async {
        guard let repostState, !quoteContent.isEmpty else { return }

        do {
            try await repostState.quote(content: quoteContent)

            showQuoteComposer = false
            quoteContent = ""

            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)
        } catch {
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.error)
        }
    }

    private func triggerHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}
