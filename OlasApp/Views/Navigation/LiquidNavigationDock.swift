import SwiftUI

enum MainTab: CaseIterable {
    case home
    case videos
    case explore
    case wallet

    var icon: String {
        switch self {
        case .home: "wave.3.up.circle"
        case .videos: "play.circle"
        case .explore: "magnifyingglass.circle"
        case .wallet: "creditcard"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: "wave.3.up.circle.fill"
        case .videos: "play.circle.fill"
        case .explore: "magnifyingglass.circle.fill"
        case .wallet: "creditcard.fill"
        }
    }

    var label: String {
        switch self {
        case .home: "Home"
        case .videos: "Videos"
        case .explore: "Explore"
        case .wallet: "Wallet"
        }
    }
}

struct LiquidNavigationDock: View {
    @Binding var selectedTab: MainTab
    @Bindable var tabBarState: TabBarState

    private let buttonSize: CGFloat = 44
    private let dockPadding: CGFloat = 6
    private let iconSize: CGFloat = 22
    private let buttonSpacing: CGFloat = 8

    private var expandedWidth: CGFloat {
        let tabCount = MainTab.allCases.count
        return CGFloat(tabCount) * buttonSize + CGFloat(max(tabCount - 1, 0)) * buttonSpacing + dockPadding * 2
    }

    private var minimizedWidth: CGFloat {
        buttonSize + dockPadding * 2
    }

    var body: some View {
        HStack(spacing: buttonSpacing) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let isActive = selectedTab == tab
                let shouldShow = !tabBarState.isMinimized || isActive

                TabBarButton(
                    icon: tab.icon,
                    selectedIcon: tab.selectedIcon,
                    accessibilityLabel: tab.label,
                    isSelected: isActive,
                    buttonSize: buttonSize,
                    iconSize: iconSize
                ) {
                    handleTabTap(tab: tab)
                }
                .frame(width: shouldShow ? buttonSize : 0, height: buttonSize)
                .opacity(shouldShow ? 1 : 0)
                .scaleEffect(shouldShow ? 1 : 0.5)
            }
        }
        .padding(dockPadding)
        .frame(width: tabBarState.isMinimized ? minimizedWidth : expandedWidth)
        .glassEffect(.regular.interactive())
        .clipShape(Capsule())
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tabBarState.isMinimized)
    }

    private func handleTabTap(tab: MainTab) {
        if tabBarState.isMinimized {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                tabBarState.setMinimized(false)
            }
        } else {
            selectedTab = tab
        }
    }
}

struct TabBarButton: View {
    let icon: String
    let selectedIcon: String
    let accessibilityLabel: String
    let isSelected: Bool
    let buttonSize: CGFloat
    let iconSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(isSelected ? 0.15 : 0))
                    .frame(width: buttonSize, height: buttonSize)

                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: iconSize, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ActionSatelliteButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    private let iconSize: CGFloat = 22

    init(accessibilityLabel: String = "Create post", action: @escaping () -> Void) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: iconSize, weight: .bold))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(accessibilityLabel)
    }
}
