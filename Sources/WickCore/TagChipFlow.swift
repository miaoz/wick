import CoreGraphics

/// A tag chip reduced to identity + precomputed width for layout math.
struct TagChipItem: Equatable {
    /// Stable identity: "all", a tag name, or "#less".
    let id: String
    let width: CGFloat
}

/// Greedy row wrapping for the journal sidebar's tag chips. Pure logic with
/// caller-supplied widths, so packing rules stay unit-testable.
enum TagChipFlow {
    static let spacing: CGFloat = 6

    /// Packs items into rows of at most `availableWidth`, preserving order.
    static func rows(items: [TagChipItem], availableWidth: CGFloat) -> [[TagChipItem]] {
        var result: [[TagChipItem]] = [[]]
        var currentWidth: CGFloat = 0

        for item in items {
            let isRowEmpty = result[result.count - 1].isEmpty
            let addedWidth = isRowEmpty ? item.width : currentWidth + spacing + item.width
            if !isRowEmpty, addedWidth > availableWidth {
                result.append([item])
                currentWidth = item.width
            } else {
                result[result.count - 1].append(item)
                currentWidth = addedWidth
            }
        }

        return result
    }

    /// Row-1 items plus a "more" toggle whose width depends on the hidden
    /// count, trimmed from the tail until chips and toggle fit together.
    /// Returns nil when everything fits a single row (no toggle needed).
    static func collapsedRow(
        items: [TagChipItem],
        availableWidth: CGFloat,
        toggleWidth: (Int) -> CGFloat
    ) -> (row: [TagChipItem], hiddenCount: Int)? {
        let packed = rows(items: items, availableWidth: availableWidth)
        guard packed.count > 1 else { return nil }

        var row = packed[0]
        var hidden = items.count - row.count
        while !row.isEmpty {
            if rowWidth(of: row) + spacing + toggleWidth(hidden) <= availableWidth {
                break
            }
            row.removeLast()
            hidden += 1
        }
        return (row, hidden)
    }

    static func rowWidth(of row: [TagChipItem]) -> CGFloat {
        row.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(row.count - 1, 0))
    }
}
