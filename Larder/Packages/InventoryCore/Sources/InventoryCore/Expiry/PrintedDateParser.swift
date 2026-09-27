import Foundation

/// A date read off a package.
public struct PrintedDate: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case useBy
        case bestBy
        case sellBy
        case unknown

        public var label: String {
            switch self {
            case .useBy: "Use by"
            case .bestBy: "Best by"
            case .sellBy: "Sell by"
            case .unknown: "Date"
            }
        }
    }

    public var date: Date
    public var kind: Kind
    /// The text the date was read from.
    public var text: String
}

/// Finds the expiry date in text recognized from a package: "BEST BY
/// 12/15/26", "EXP 2027-03-01", "USE BY 15 DEC 2026", "SELL BY OCT 03",
/// "BB 15.12.26", "EXP 06/2028" (the end of that month). Lot codes and
/// times are ignored, dates near a "best by"/"use by" label win, and
/// implausible dates (years away) are dropped.
public enum PrintedDateParser {
    static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    static let monthPattern = "(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*\\.?"

    static let labels: [(pattern: String, kind: PrintedDate.Kind)] = [
        ("BEST\\s*IF\\s*USED\\s*BY", .bestBy),
        ("BEST\\s*BEFORE", .bestBy),
        ("BEST\\s*BY", .bestBy),
        ("ENJOY\\s*BY", .bestBy),
        ("FRESH\\s*UNTIL", .bestBy),
        ("\\bBBE?\\b", .bestBy),
        ("USE\\s*-?\\s*BY", .useBy),
        ("\\bEXP(?:IRES|IRY|IRATION)?\\b", .useBy),
        ("SELL\\s*-?\\s*BY", .sellBy),
    ]

    /// - Parameter dayFirst: read "05/06/27" as 5 June rather than May 6.
    public static func parse(_ text: String, now: Date, dayFirst: Bool = false, calendar: Calendar = .current) -> PrintedDate? {
        candidates(text, now: now, dayFirst: dayFirst, calendar: calendar).first
    }

    /// Every plausible date in the text, best first.
    public static func candidates(_ text: String, now: Date, dayFirst: Bool = false, calendar: Calendar = .current) -> [PrintedDate] {
        let upper = text.uppercased()
        let labelHits = labels.flatMap { label in
            matches(label.pattern, in: upper).map { (range: $0.range, kind: label.kind) }
        }
        var found: [(date: PrintedDate, score: Double, location: Int)] = []
        var claimed: [NSRange] = []

        func consider(_ match: NSTextCheckingResult, date: Date?, hasYear: Bool) {
            guard let date, !claimed.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return }
            claimed.append(match.range)
            // Nothing sensible is years past its date or a decade away.
            guard let earliest = calendar.date(byAdding: .year, value: -2, to: now),
                  let latest = calendar.date(byAdding: .year, value: 10, to: now),
                  date >= earliest, date <= latest
            else { return }
            let label = labelHits
                .filter { $0.range.location + $0.range.length <= match.range.location && match.range.location - ($0.range.location + $0.range.length) <= 20 }
                .max { $0.range.location < $1.range.location }
            var score = 0.0
            if label != nil { score += 3 }
            if hasYear { score += 1 }
            if let recent = calendar.date(byAdding: .day, value: -30, to: now), date >= recent { score += 1 }
            let snippet = (upper as NSString).substring(with: match.range)
            found.append((PrintedDate(date: date, kind: label?.kind ?? .unknown, text: snippet), score, match.range.location))
        }

        // 2026-12-15
        for match in matches("\\b(20\\d{2})[-/.](\\d{1,2})[-/.](\\d{1,2})\\b", in: upper) {
            let (y, m, d) = (int(match, 1, upper), int(match, 2, upper), int(match, 3, upper))
            consider(match, date: make(year: y, month: m, day: d, calendar: calendar), hasYear: true)
        }
        // 15 DEC 2026, 15DEC26
        for match in matches("\\b(\\d{1,2})\\s*-?\\s*\(monthPattern)\\s*-?\\s*,?\\s*(\\d{4}|\\d{2})\\b", in: upper) {
            let day = int(match, 1, upper)
            let month = monthIndex(match, 2, upper)
            let year = fullYear(int(match, 3, upper))
            consider(match, date: make(year: year, month: month, day: day, calendar: calendar), hasYear: true)
        }
        // DEC 15 2026, DEC 15, 26
        for match in matches("\\b\(monthPattern)\\s*-?\\s*(\\d{1,2})(?:ST|ND|RD|TH)?(?:\\s*[,-]\\s*|\\s+)(\\d{4}|\\d{2})\\b", in: upper) {
            let month = monthIndex(match, 1, upper)
            let day = int(match, 2, upper)
            let year = fullYear(int(match, 3, upper))
            consider(match, date: make(year: year, month: month, day: day, calendar: calendar), hasYear: true)
        }
        // 12/15/26, 15.12.2026
        for match in matches("\\b(\\d{1,2})[/.\\-](\\d{1,2})[/.\\-](\\d{4}|\\d{2})\\b", in: upper) {
            let (a, b) = (int(match, 1, upper), int(match, 2, upper))
            let year = fullYear(int(match, 3, upper))
            let (month, day) = a > 12 || (dayFirst && b <= 12) ? (b, a) : (a, b)
            consider(match, date: make(year: year, month: month, day: day, calendar: calendar), hasYear: true)
        }
        // 06/2028: the end of that month
        for match in matches("\\b(\\d{1,2})[/\\-](20\\d{2})\\b", in: upper) {
            consider(match, date: endOfMonth(year: int(match, 2, upper), month: int(match, 1, upper), calendar: calendar), hasYear: true)
        }
        // DEC 2026, or DEC 26 (a day when that's soon, otherwise a year)
        for match in matches("\\b\(monthPattern)\\s*[-/]?\\s*(\\d{4}|\\d{1,2})\\b", in: upper) {
            let month = monthIndex(match, 1, upper)
            let number = int(match, 2, upper)
            if number > 31 || String(number).count == 4 {
                consider(match, date: endOfMonth(year: fullYear(number), month: month, calendar: calendar), hasYear: true)
            } else if let nextDay = nextOccurrence(month: month, day: number, after: now, calendar: calendar),
                      let soon = calendar.date(byAdding: .day, value: 45, to: now), nextDay <= soon {
                consider(match, date: nextDay, hasYear: false)
            } else {
                consider(match, date: endOfMonth(year: fullYear(number), month: month, calendar: calendar), hasYear: true)
            }
        }
        // BEST BY 12/15: only right after a label
        for match in matches("\\b(\\d{1,2})[/.](\\d{1,2})\\b", in: upper) {
            let (a, b) = (int(match, 1, upper), int(match, 2, upper))
            let (month, day) = a > 12 || (dayFirst && b <= 12) ? (b, a) : (a, b)
            let labeled = labelHits.contains { match.range.location - ($0.range.location + $0.range.length) >= 0 && match.range.location - ($0.range.location + $0.range.length) <= 6 }
            guard labeled else { continue }
            consider(match, date: nextOccurrence(month: month, day: day, after: calendar.date(byAdding: .day, value: -30, to: now) ?? now, calendar: calendar), hasYear: false)
        }

        return found
            .sorted { ($0.score, -$0.location) > ($1.score, -$1.location) }
            .map(\.date)
    }

    // MARK: - Helpers

    static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    static func int(_ match: NSTextCheckingResult, _ group: Int, _ text: String) -> Int {
        let range = match.range(at: group)
        guard range.location != NSNotFound else { return 0 }
        return Int((text as NSString).substring(with: range)) ?? 0
    }

    static func monthIndex(_ match: NSTextCheckingResult, _ group: Int, _ text: String) -> Int {
        let range = match.range(at: group)
        guard range.location != NSNotFound else { return 0 }
        let name = (text as NSString).substring(with: range)
        return (months.firstIndex(of: String(name.prefix(3))) ?? -1) + 1
    }

    static func fullYear(_ year: Int) -> Int {
        year < 100 ? 2000 + year : year
    }

    static func make(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day), (2000...2100).contains(year) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month
        else { return nil }
        return date
    }

    static func endOfMonth(year: Int, month: Int, calendar: Calendar) -> Date? {
        guard let first = make(year: year, month: month, day: 1, calendar: calendar),
              let next = calendar.date(byAdding: .month, value: 1, to: first)
        else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: next)
    }

    /// The first `month`/`day` on or after `date`.
    static func nextOccurrence(month: Int, day: Int, after date: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: date)
        let start = calendar.startOfDay(for: date)
        for candidate in [year, year + 1] {
            if let result = make(year: candidate, month: month, day: day, calendar: calendar), result >= start {
                return result
            }
        }
        return nil
    }
}
