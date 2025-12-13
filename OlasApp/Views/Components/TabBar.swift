import SwiftUI

/// Reusable tab bar component with selectable tabs
public struct TabBar<Tab: RawRepresentable & CaseIterable & Hashable>: View where Tab.RawValue == String {
    @Binding var selectedTab: Tab
    let tabs: [Tab]

    public init(selectedTab: Binding<Tab>, tabs: [Tab]? = nil) {
        _selectedTab = selectedTab
        self.tabs = tabs ?? Array(Tab.allCases)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { tab in
                    TabButton(
                        title: tab.rawValue,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
            }

            Divider()
        }
    }
}

/// Individual tab button
public struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    public init(title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)

                Rectangle()
                    .fill(isSelected ? Color.primary : Color.clear)
                    .frame(height: 1)
            }
        }
    }
}
