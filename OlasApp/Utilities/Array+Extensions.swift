// Array+Extensions.swift
import Foundation

extension Array {
    /// Finds the insertion index for an element using binary search
    /// - Parameters:
    ///   - element: The element to insert
    ///   - comparator: A closure that returns true if the first element should come before the second
    /// - Returns: The index where the element should be inserted to maintain sorted order
    func insertionIndex(
        for element: Element,
        using comparator: (Element, Element) -> Bool
    ) -> Int {
        var low = 0
        var high = count

        while low < high {
            let mid = (low + high) / 2
            if comparator(element, self[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }

        return low
    }
}
