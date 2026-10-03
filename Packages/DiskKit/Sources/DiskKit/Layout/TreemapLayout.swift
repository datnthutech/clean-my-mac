import Foundation

public struct LayoutRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var area: Double { width * height }
}

/// Squarified treemap (Bruls, Huizing, van Wijk) — keeps tiles close to square so labels stay readable.
public enum TreemapLayout {
    public struct Tile<ID: Hashable>: Equatable where ID: Equatable {
        public let id: ID
        public let rect: LayoutRect
    }

    /// Lays out `items` (any order; non-positive values are dropped) inside `bounds`.
    public static func squarify<ID: Hashable>(_ items: [(id: ID, value: Double)], in bounds: LayoutRect) -> [Tile<ID>] {
        let positive = items.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let total = positive.reduce(0) { $0 + $1.value }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return [] }

        let scale = bounds.area / total
        let areas = positive.map { $0.value * scale }
        var tiles: [Tile<ID>] = []
        tiles.reserveCapacity(positive.count)
        var remaining = bounds
        var index = 0

        while index < areas.count {
            let side = min(remaining.width, remaining.height)
            var rowEnd = index + 1
            var rowSum = areas[index]
            var rowMin = areas[index]
            var rowMax = areas[index]
            var currentWorst = worst(sum: rowSum, min: rowMin, max: rowMax, side: side)

            while rowEnd < areas.count {
                let candidate = areas[rowEnd]
                let nextSum = rowSum + candidate
                let nextWorst = worst(sum: nextSum, min: min(rowMin, candidate), max: max(rowMax, candidate), side: side)
                if nextWorst > currentWorst { break }
                rowSum = nextSum
                rowMin = min(rowMin, candidate)
                rowMax = max(rowMax, candidate)
                currentWorst = nextWorst
                rowEnd += 1
            }

            // Lay the row along the shorter side of the remaining rectangle.
            if remaining.width >= remaining.height {
                let columnWidth = remaining.height > 0 ? rowSum / remaining.height : 0
                var y = remaining.y
                for i in index..<rowEnd {
                    let height = columnWidth > 0 ? areas[i] / columnWidth : 0
                    tiles.append(Tile(id: positive[i].id, rect: LayoutRect(x: remaining.x, y: y, width: columnWidth, height: height)))
                    y += height
                }
                remaining.x += columnWidth
                remaining.width = max(0, remaining.width - columnWidth)
            } else {
                let rowHeight = remaining.width > 0 ? rowSum / remaining.width : 0
                var x = remaining.x
                for i in index..<rowEnd {
                    let width = rowHeight > 0 ? areas[i] / rowHeight : 0
                    tiles.append(Tile(id: positive[i].id, rect: LayoutRect(x: x, y: remaining.y, width: width, height: rowHeight)))
                    x += width
                }
                remaining.y += rowHeight
                remaining.height = max(0, remaining.height - rowHeight)
            }
            index = rowEnd
        }
        return tiles
    }

    /// Worst aspect ratio in a row — lower is better.
    private static func worst(sum: Double, min: Double, max: Double, side: Double) -> Double {
        guard sum > 0, min > 0, side > 0 else { return .infinity }
        let side2 = side * side
        let sum2 = sum * sum
        return Swift.max(side2 * max / sum2, sum2 / (side2 * min))
    }
}
