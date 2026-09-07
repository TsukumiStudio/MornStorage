import CoreGraphics

enum Treemap {
    /// Squarified treemap. `weights` must be sorted descending; zero weights get a zero rect.
    static func layout(_ weights: [Double], in bounds: CGRect) -> [CGRect] {
        var rects = Array(repeating: CGRect.zero, count: weights.count)
        let total = weights.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return rects }
        let scale = bounds.width * bounds.height / total
        var remaining = bounds
        var row: [Int] = []
        var rowSum = 0.0, rowMin = Double.infinity, rowMax = 0.0
        var index = 0

        func worst(_ sum: Double, _ minimum: Double, _ maximum: Double, _ side: Double) -> Double {
            max(side * side * maximum / (sum * sum), sum * sum / (side * side * minimum))
        }
        func flush() {
            guard !row.isEmpty else { return }
            let vertical = remaining.width >= remaining.height
            let thickness = rowSum / (vertical ? remaining.height : remaining.width)
            var offset = vertical ? remaining.minY : remaining.minX
            for item in row {
                let length = weights[item] * scale / thickness
                rects[item] = vertical
                    ? CGRect(x: remaining.minX, y: offset, width: thickness, height: length)
                    : CGRect(x: offset, y: remaining.minY, width: length, height: thickness)
                offset += length
            }
            if vertical { remaining.origin.x += thickness; remaining.size.width -= thickness }
            else { remaining.origin.y += thickness; remaining.size.height -= thickness }
            row = []; rowSum = 0; rowMin = .infinity; rowMax = 0
        }

        while index < weights.count {
            let area = weights[index] * scale
            if area <= 0 { break }
            let side = min(remaining.width, remaining.height)
            if row.isEmpty || worst(rowSum + area, min(rowMin, area), max(rowMax, area), side) <= worst(rowSum, rowMin, rowMax, side) {
                row.append(index); rowSum += area; rowMin = min(rowMin, area); rowMax = max(rowMax, area)
                index += 1
            } else {
                flush()
            }
        }
        flush()
        return rects
    }
}
