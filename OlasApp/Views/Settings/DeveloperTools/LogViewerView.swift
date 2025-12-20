import NDKSwiftCore
import SwiftUI

struct LogViewerView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Log Viewer Unavailable")
                .font(.headline)

            Text("The logging API has changed in the latest NDKSwift version. This feature will be updated in a future release.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Logs")
    }
}

#Preview {
    NavigationStack {
        LogViewerView()
    }
}
