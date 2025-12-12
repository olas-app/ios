import SwiftUI
import NDKSwiftCore

public struct GridItemView: View {
    let event: NDKEvent
    let onTap: (NDKEvent) -> Void

    private var image: NDKImage {
        NDKImage(event: event)
    }

    public init(event: NDKEvent, onTap: @escaping (NDKEvent) -> Void) {
        self.event = event
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(
                    url: url,
                    blurhash: image.primaryBlurhash,
                    aspectRatio: image.primaryAspectRatio
                ) { loadedImage in
                    loadedImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                }
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .onTapGesture {
            onTap(event)
        }
    }
}
