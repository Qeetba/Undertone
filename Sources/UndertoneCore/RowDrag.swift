import Foundation

/// One queue row being dragged up or down among its neighbours: where it would land
/// if dropped now, and where every row should be drawn in the meantime.
public struct RowDrag: Equatable {
    /// Index of the row being dragged.
    public let source: Int
    /// Number of rows in the list.
    public let count: Int
    public let rowHeight: Double
    /// How far the pointer has moved vertically since the drag began.
    public var translation: Double = 0

    public init(source: Int, count: Int, rowHeight: Double) {
        self.source = source
        self.count = count
        self.rowHeight = rowHeight
    }

    /// The slot the dragged row would occupy if dropped now.
    public var destination: Int {
        let slots = Int((translation / rowHeight).rounded())
        return min(max(source + slots, 0), max(count - 1, 0))
    }

    /// How far to draw the row at `index` from its resting place. The dragged row
    /// follows the pointer, held inside the list; the rows it passes shift one slot
    /// the other way to make room.
    public func offset(forRowAt index: Int) -> Double {
        if index == source {
            let highest = -Double(source) * rowHeight
            let lowest = Double(max(count - 1, 0) - source) * rowHeight
            return min(max(translation, highest), lowest)
        }
        if source < index, index <= destination { return -rowHeight }
        if destination <= index, index < source { return rowHeight }
        return 0
    }

    /// The reorder to apply on drop, in the form `Playlist.move` takes, or nil if the
    /// row is back where it started.
    public var move: (source: IndexSet, destination: Int)? {
        guard destination != source else { return nil }
        // An insertion point counts positions before the row is taken out, so moving
        // down has to aim one past the slot it will end up in.
        return (IndexSet(integer: source), destination > source ? destination + 1 : destination)
    }
}
