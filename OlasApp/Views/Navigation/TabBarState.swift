import SwiftUI

@Observable
public final class TabBarState {
    public var isMinimized: Bool = false

    private var previousOffset: CGFloat = 0
    private var accumulatedDelta: CGFloat = 0
    private let minimizeThreshold: CGFloat = 100
    private let expandThreshold: CGFloat = 50

    public init() {}

    public func updateScrollOffset(_ offset: CGFloat) {
        let delta = offset - previousOffset
        previousOffset = offset

        if delta > 0 {
            handleScrollDown(delta: delta)
        } else if delta < 0 {
            handleScrollUp(delta: delta)
        }
    }

    public func resetScroll() {
        previousOffset = 0
        accumulatedDelta = 0
    }

    public func setMinimized(_ minimized: Bool) {
        isMinimized = minimized
    }

    private func handleScrollDown(delta: CGFloat) {
        if accumulatedDelta < 0 {
            accumulatedDelta = 0
        }
        accumulatedDelta += delta

        if accumulatedDelta > minimizeThreshold && !isMinimized {
            isMinimized = true
            accumulatedDelta = 0
        }
    }

    private func handleScrollUp(delta: CGFloat) {
        if accumulatedDelta > 0 {
            accumulatedDelta = 0
        }
        accumulatedDelta += delta

        if accumulatedDelta < -expandThreshold && isMinimized {
            isMinimized = false
            accumulatedDelta = 0
        }
    }
}
