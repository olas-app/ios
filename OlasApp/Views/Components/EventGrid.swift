import SwiftUI
import NDKSwiftCore

public struct EventGrid: View {
    let ndk: NDK
    let filter: NDKFilter
    let onTap: (NDKEvent) -> Void
    let namespace: Namespace.ID

    @State private var events: [NDKEvent] = []

    public init(ndk: NDK, filter: NDKFilter, onTap: @escaping (NDKEvent) -> Void, namespace: Namespace.ID) {
        self.ndk = ndk
        self.filter = filter
        self.onTap = onTap
        self.namespace = namespace
    }

    public var body: some View {
        PostGridView(posts: events, spacing: 1, onTap: onTap, namespace: namespace)
            .task {
                await subscribeToEvents()
            }
    }

    private func subscribeToEvents() async {
        let subscription = ndk.subscribe(filter: filter, cachePolicy: .cacheWithNetwork)
        for await eventBatch in subscription.events {
            for event in eventBatch {
                let insertIndex = events.firstIndex { event.createdAt > $0.createdAt } ?? events.endIndex
                events.insert(event, at: insertIndex)
            }
        }
    }
}
