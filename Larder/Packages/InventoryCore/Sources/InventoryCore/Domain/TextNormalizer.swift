import Foundation

/// Normalizes free text (product names, receipt lines, barcodes) so it can be
/// compared and used as a lookup key.
public enum TextNormalizer {
    /// Lowercased, diacritic-folded, punctuation stripped, whitespace collapsed.
    /// "  Great-Value WHOLE Milk, 1 GAL " → "great value whole milk 1 gal"
    public static func key(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var result = ""
        result.reserveCapacity(folded.count)
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "%" {
                if pendingSpace && !result.isEmpty { result.append(" ") }
                pendingSpace = false
                result.unicodeScalars.append(scalar)
            } else {
                pendingSpace = true
            }
        }
        // Periods only matter inside numbers ("1.5"); drop the rest.
        return result
            .split(separator: " ")
            .map { token in
                token.contains(where: \.isNumber) ? String(token) : token.replacingOccurrences(of: ".", with: "")
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Search tokens for a query string.
    public static func tokens(_ text: String) -> [String] {
        key(text).split(separator: " ").map(String.init)
    }

    /// Barcodes: digits only. UPC-A codes are widened to EAN-13 so the same
    /// product scanned as UPC-A or EAN-13 maps to one key.
    public static func barcode(_ text: String) -> String {
        let digits = text.filter(\.isNumber)
        if digits.count == 12 { return "0" + digits }
        return digits
    }
}
