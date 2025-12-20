import NDKSwiftCore
import SwiftUI

struct NetworkTrafficView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Network Traffic Unavailable")
                .font(.headline)

            Text("The network monitoring API has changed in the latest NDKSwift version. This feature will be updated in a future release.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Network Traffic")
    }
}

#Preview {
    NavigationStack {
        NetworkTrafficView()
    }
}
