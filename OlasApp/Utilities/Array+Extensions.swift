// Array+Extensions.swift
import Foundation

extension Array {
    /// Finds the insertion index for an element using binary search
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

    /// Finds insertion index with diversity enforcement.
    /// After `maxConsecutive` posts from the same group key appear in a row,
    /// subsequent posts get pushed down exponentially (2, 4, 8, 16...).
    func diversifiedInsertionIndex(
        for element: Element,
        sortedBy comparator: (Element, Element) -> Bool,
        groupKey: KeyPath<Element, String>,
        maxConsecutive: Int = 3
    ) -> Int {
        let natural = insertionIndex(for: element, using: comparator)
        let key = element[keyPath: groupKey]

        // Count consecutive same-key elements immediately above insertion point
        var consecutive = 0
        for i in stride(from: natural - 1, through: 0, by: -1) {
            if self[i][keyPath: groupKey] == key {
                consecutive += 1
            } else {
                break
            }
        }

        guard consecutive >= maxConsecutive else { return natural }

        // Push down exponentially: 2, 4, 8, 16...
        let offset = 1 << (consecutive - maxConsecutive + 1)
        return Swift.min(natural + offset, count)
    }
}
