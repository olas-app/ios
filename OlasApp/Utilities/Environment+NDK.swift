import NDKSwiftCore
import SwiftUI

private struct NDKEnvironmentKey: EnvironmentKey {
    static let defaultValue: NDK? = nil
}

extension EnvironmentValues {
    var ndk: NDK? {
        get { self[NDKEnvironmentKey.self] }
        set { self[NDKEnvironmentKey.self] = newValue }
    }
}
