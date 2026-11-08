import Foundation

/// Numéros de téléphone : format international (E.164) et détection des mobiles.
public enum PhoneNumber {
    /// « 06 12 34 56 78 », « 0033 6… », « +33 (0)6… » → « +33612345678 ». `nil` si le numéro est inexploitable.
    public static func e164(_ raw: String, defaultCountryCode: String = "33") -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "(0)", with: "")
        let hasPlus = text.hasPrefix("+")
        var digits = text.filter(\.isASCIIDigitCharacter)
        guard !digits.isEmpty else { return nil }
        if hasPlus {
            // déjà international
        } else if digits.hasPrefix("00") {
            digits.removeFirst(2)
        } else if digits.hasPrefix("0") && digits.count == 10 {
            digits = defaultCountryCode + digits.dropFirst()
        } else if digits.count == 9 && defaultCountryCode == "33" && (digits.hasPrefix("6") || digits.hasPrefix("7")) {
            digits = defaultCountryCode + digits
        } else if digits.count < 11 {
            return nil
        }
        guard (8...15).contains(digits.count) else { return nil }
        return "+" + digits
    }

    /// Mobile probable : 06 / 07 en France ; à l'étranger on ne sait pas, on considère que oui.
    public static func isLikelyMobile(_ e164: String) -> Bool {
        guard e164.hasPrefix("+33") else { return true }
        return e164.hasPrefix("+336") || e164.hasPrefix("+337")
    }

    /// Affichage lisible : « +33 6 12 34 56 78 » pour la France, sinon le numéro international.
    public static func display(_ e164: String) -> String {
        guard e164.hasPrefix("+33"), e164.count == 12 else { return e164 }
        let national = Array(e164.dropFirst(3))
        var groups = [String(national[0])]
        var index = 1
        while index < national.count {
            groups.append(String(national[index..<min(index + 2, national.count)]))
            index += 2
        }
        return "+33 " + groups.joined(separator: " ")
    }
}

private extension Character {
    var isASCIIDigitCharacter: Bool { ("0"..."9").contains(self) }
}
