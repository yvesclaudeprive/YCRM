import Foundation

/// Formats français écrits à la main (identiques sur iPhone et en CI Linux) :
/// nombres « 7 356,50 », dates « JJ/MM/AAAA », heures « JJ/MM/AAAA à HH:MM » (heure de Paris).
public enum FrenchFormat {
    /// Espace insécable fine entre milliers, comme dans Pipedrive en français.
    public static let thousandsSeparator = "\u{202F}"

    public static func number(_ value: Double, maxDecimals: Int = 2, minDecimals: Int = 0) -> String {
        guard value.isFinite else { return "—" }
        let factor = pow(10.0, Double(maxDecimals))
        let rounded = (abs(value) * factor).rounded() / factor
        let negative = value < 0 && rounded != 0
        let integerPart = rounded.rounded(.down)
        var fraction = Int(((rounded - integerPart) * factor).rounded())
        var integerValue = integerPart
        if fraction >= Int(factor) { // garde-fou d'arrondi
            fraction = 0
            integerValue += 1
        }
        let digits = String(format: "%.0f", integerValue)
        var grouped = ""
        for (index, character) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { grouped += thousandsSeparator }
            grouped.append(character)
        }
        var decimals = maxDecimals > 0 ? String(format: "%0\(maxDecimals)ld", fraction) : ""
        while decimals.count > minDecimals && decimals.hasSuffix("0") { decimals.removeLast() }
        let body = decimals.isEmpty ? grouped : grouped + "," + decimals
        return negative ? "-" + body : body
    }

    public static func integer(_ value: Int) -> String {
        number(Double(value), maxDecimals: 0)
    }

    public static func money(_ amount: Double, currency: String) -> String {
        let symbols = ["EUR": "€", "USD": "$", "GBP": "£", "CHF": "CHF"]
        return number(amount, maxDecimals: 2, minDecimals: 2) + "\u{00A0}" + (symbols[currency.uppercased()] ?? currency)
    }

    /// Lit un nombre saisi à la française : « 1 600,50 », « 1600.5 », « 12 ».
    public static func parseNumber(_ text: String) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" ", "\u{00A0}", "\u{202F}", "€"] {
            cleaned = cleaned.replacingOccurrences(of: separator, with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// « 2026-07-08 » → « 08/07/2026 ». « 2025-12-01T14:12:54Z » → « 01/12/2025 à 15:12 » (heure de Paris).
    public static func date(fromAPI text: String) -> String {
        if let parts = dayParts(text), text.count == 10 {
            return String(format: "%02ld/%02ld/%04ld", parts.day, parts.month, parts.year)
        }
        if let instant = parseInstant(text) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
            let day = String(format: "%02ld/%02ld/%04ld", c.day ?? 0, c.month ?? 0, c.year ?? 0)
            if (c.hour ?? 0) == 0 && (c.minute ?? 0) == 0 { return day }
            return day + String(format: " à %02ld:%02ld", c.hour ?? 0, c.minute ?? 0)
        }
        return text
    }

    static let monthNames = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août",
                             "septembre", "octobre", "novembre", "décembre"]

    /// Date en toutes lettres (demande d'Yves pour l'app) : « 2 novembre », « 1er mars à 14:30 »,
    /// avec l'année seulement si elle diffère de l'année en cours : « 12 décembre 2025 ».
    public static func longDate(fromAPI text: String, now: Date = Date(), timeZone: TimeZone? = nil) -> String {
        let zone = timeZone ?? TimeZone(identifier: "Europe/Paris") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let currentYear = calendar.component(.year, from: now)
        func words(day: Int, month: Int, year: Int) -> String {
            let dayText = day == 1 ? "1er" : String(day)
            let monthText = (1...12).contains(month) ? monthNames[month - 1] : String(month)
            return year == currentYear ? "\(dayText) \(monthText)" : "\(dayText) \(monthText) \(year)"
        }
        if let parts = dayParts(text), text.count == 10 {
            return words(day: parts.day, month: parts.month, year: parts.year)
        }
        if let instant = parseInstant(text) {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
            let day = words(day: c.day ?? 1, month: c.month ?? 1, year: c.year ?? currentYear)
            if (c.hour ?? 0) == 0 && (c.minute ?? 0) == 0 { return day }
            return day + String(format: " à %02ld:%02ld", c.hour ?? 0, c.minute ?? 0)
        }
        return text
    }

    /// Date du calendrier (sans heure) au format API « AAAA-MM-JJ ».
    public static func apiDay(from date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// « AAAA-MM-JJ » → date à midi (évite les décalages de fuseau dans le sélecteur de date).
    public static func date(fromAPIDay text: String, timeZone: TimeZone = .current) -> Date? {
        guard let parts = dayParts(text) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12))
    }

    static func dayParts(_ text: String) -> (year: Int, month: Int, day: Int)? {
        let pieces = text.prefix(10).split(separator: "-")
        guard pieces.count == 3, let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return (year, month, day)
    }

    static func parseInstant(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        // Avec millisecondes : « 2026-11-03T19:14:30.000Z » (e-mails synchronisés) : on les retire.
        let withoutFraction = text.replacingOccurrences(of: #"\.[0-9]+(?=Z|[+-][0-9])"#, with: "", options: .regularExpression)
        if withoutFraction != text, let date = formatter.date(from: withoutFraction) { return date }
        // Ancien format Pipedrive : « 2025-12-01 14:12:54 » (UTC)
        let normalized = text.replacingOccurrences(of: " ", with: "T") + "Z"
        return formatter.date(from: normalized)
    }
}
