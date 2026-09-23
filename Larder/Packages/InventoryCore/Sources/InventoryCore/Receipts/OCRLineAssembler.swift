import Foundation

/// A piece of text recognized by OCR, with a normalized bounding box.
///
/// Coordinates follow Vision: origin at the bottom-left, values 0...1.
public struct RecognizedTextFragment: Sendable, Equatable {
    public var text: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var confidence: Double

    public init(text: String, x: Double, y: Double, width: Double, height: Double, confidence: Double = 1) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.confidence = confidence
    }

    var top: Double { y + height }
    var bottom: Double { y }
    var midY: Double { y + height / 2 }
    var maxX: Double { x + width }
}

/// Rebuilds receipt rows from OCR fragments.
///
/// Vision returns the item description and its price as separate observations
/// because of the gap between the columns. Fragments whose vertical extents
/// overlap by at least half the smaller height belong to the same row; within a
/// row they are ordered left to right, and wide gaps become runs of spaces so
/// the price column stays visually separate.
public enum OCRLineAssembler {
    /// Horizontal gap (fraction of page width) that counts as a column break.
    static let columnGap = 0.04

    public static func lines(from fragments: [RecognizedTextFragment], minimumConfidence: Double = 0.2) -> [String] {
        let usable = fragments.filter {
            $0.confidence >= minimumConfidence && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        // Top of the page first.
        let sorted = usable.sorted { $0.midY > $1.midY }

        var rows: [[RecognizedTextFragment]] = []
        for fragment in sorted {
            if let index = rows.lastIndex(where: { belongsToRow(fragment, $0) }) {
                rows[index].append(fragment)
            } else {
                rows.append([fragment])
            }
        }

        return rows.map { row in
            let ordered = row.sorted { $0.x < $1.x }
            var line = ""
            var previous: RecognizedTextFragment?
            for fragment in ordered {
                if let previous {
                    line += fragment.x - previous.maxX > columnGap ? "    " : " "
                }
                line += fragment.text.trimmingCharacters(in: .whitespaces)
                previous = fragment
            }
            return line
        }
    }

    /// Lines for a multi-page capture, pages in order.
    public static func text(fromPages pages: [[RecognizedTextFragment]]) -> String {
        pages.map { lines(from: $0).joined(separator: "\n") }.joined(separator: "\n")
    }

    static func belongsToRow(_ fragment: RecognizedTextFragment, _ row: [RecognizedTextFragment]) -> Bool {
        // Compare against the row's vertical band.
        guard let top = row.map(\.top).max(), let bottom = row.map(\.bottom).min() else { return false }
        let rowHeight = row.map(\.height).reduce(0, +) / Double(row.count)
        let overlap = min(top, fragment.top) - max(bottom, fragment.bottom)
        return overlap >= 0.5 * min(rowHeight, fragment.height)
    }
}
