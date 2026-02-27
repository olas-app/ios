import SwiftUI

enum MainTab: CaseIterable, Hashable {
    case home
    case videos
    case createPost
    case explore
    case wallet

    var icon: String {
        switch self {
        case .home: "wave.3.up.circle"
        case .videos: "play.circle"
        case .createPost: "plus"
        case .explore: "magnifyingglass.circle"
        case .wallet: "creditcard"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: "wave.3.up.circle.fill"
        case .videos: "play.circle.fill"
        case .createPost: "plus"
        case .explore: "magnifyingglass.circle.fill"
        case .wallet: "creditcard.fill"
        }
    }

    var label: String {
        switch self {
        case .home: "Home"
        case .videos: "Videos"
        case .createPost: "New Post"
        case .explore: "Explore"
        case .wallet: "Wallet"
        }
    }
}
