import Foundation

/// Normalization for receipt item text, used as the key when remembering how
/// a receipt line maps to a product.
public enum ReceiptText {
    /// Normalizes a receipt description so the same item keys identically on
    /// every receipt: drops item codes (6+ digit runs), prices ("3.42"),
    /// trailing tax/food flags ("F", "N", "X"), then applies `TextNormalizer.key`.
    ///
    /// "GV WHL MLK 1G   007874237193 F   3.42 N" → "gv whl mlk 1g"
    public static func key(_ text: String) -> String {
        var tokens = TextNormalizer.key(text).split(separator: " ").map(String.init)
        tokens.removeAll { token in
            isItemCode(token) || isPrice(token)
        }
        while let last = tokens.last, last.count == 1, last.first?.isLetter == true, tokens.count > 1 {
            tokens.removeLast()
        }
        return tokens.joined(separator: " ")
    }

    static func isItemCode(_ token: String) -> Bool {
        token.count >= 6 && token.allSatisfy(\.isNumber)
    }

    static func isPrice(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count == 2 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    /// Converts a decimal amount to minor units (cents), rounding half up.
    public static func cents(_ amount: Double?) -> Int? {
        guard let amount, amount.isFinite else { return nil }
        return Int((amount * 100).rounded())
    }

    /// Parses the ISO-8601 date ("2026-09-21") the extraction schema asks for.
    public static func date(fromISO text: String?, calendar: Calendar = .current) -> Date? {
        guard let text else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let date = calendar.date(from: components),
              calendar.component(.month, from: date) == parts[1]
        else { return nil }
        return date
    }
}
