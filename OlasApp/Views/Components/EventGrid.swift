import SwiftUI
import NDKSwiftCore

public struct EventGrid: View {
    let ndk: NDK
    let filter: NDKFilter
    let onTap: (NDKEvent) -> Void

    @State private var events: [NDKEvent] = []

    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    public init(ndk: NDK, filter: NDKFilter, onTap: @escaping (NDKEvent) -> Void) {
        self.ndk = ndk
        self.filter = filter
        self.onTap = onTap
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(events) { event in
                GridItemView(event: event, onTap: onTap)
            }
        }
        .task {
            await subscribeToEvents()
        }
    }

    private func subscribeToEvents() async {
        let subscription = ndk.subscribe(filter: filter)
        for await event in subscription.events {
            let insertIndex = events.firstIndex { event.createdAt > $0.createdAt } ?? events.endIndex
            events.insert(event, at: insertIndex)
        }
    }
}
