import Foundation

/// Score saisi à la main (demande d'Yves du 25/11/2026). « Modifier le score » écrit le « Score priorisation » de
/// l'affaire et passe « Source de la qualification » à « Manuel » : le calcul automatique n'y touche plus (score
/// verrouillé, cadenas sur la carte). « Score auto » remet la source à « Extraction » : le score redevient automatique.
/// Champs et valeurs retrouvés par leur nom (jamais de code en dur).
public struct ScoreFields: Hashable, Sendable {
    public static let sourceFieldName = "Source de la qualification"
    public static let manualLabel = "Manuel"
    public static let automaticLabel = "Extraction"

    public let scoreCode: String
    public let sourceCode: String?
    public let manualOptionID: Int?
    public let automaticOptionID: Int?

    public init(scoreCode: String, sourceCode: String?, manualOptionID: Int?, automaticOptionID: Int?) {
        self.scoreCode = scoreCode
        self.sourceCode = sourceCode
        self.manualOptionID = manualOptionID
        self.automaticOptionID = automaticOptionID
    }

    /// Nil sans champ « Score priorisation ».
    public init?(fields: [FieldDefinition]) {
        guard let score = fields.first(where: { Label.matches($0.name, ActivityFeedLoader.scoreFieldName) }) else {
            return nil
        }
        let source = fields.first { Label.matches($0.name, Self.sourceFieldName) }
        self.init(scoreCode: score.code, sourceCode: source?.code,
                  manualOptionID: source?.options.first { Label.matches($0.label, Self.manualLabel) }?.id,
                  automaticOptionID: source?.options.first { Label.matches($0.label, Self.automaticLabel) }?.id)
    }

    /// Valeurs écrites par « Modifier le score » : le score, et la source « Manuel » si elle existe.
    public func manualValues(score: Double) -> [String: JSONValue] {
        var values: [String: JSONValue] = [scoreCode: Self.number(score)]
        if let sourceCode, let manualOptionID { values[sourceCode] = .int(manualOptionID) }
        return values
    }

    /// Valeurs écrites par « Score auto » : la source « Extraction » (nil si le champ ou la valeur manque).
    public var automaticValues: [String: JSONValue]? {
        guard let sourceCode, let automaticOptionID else { return nil }
        return [sourceCode: .int(automaticOptionID)]
    }

    /// Valeurs d'avant, pour « Annuler » : l'ancien score et l'ancienne source.
    public func restoreValues(score: Double?, manual: Bool) -> [String: JSONValue] {
        var values: [String: JSONValue] = [scoreCode: score.map(Self.number) ?? .null]
        if let sourceCode {
            let option = manual ? manualOptionID : automaticOptionID
            values[sourceCode] = option.map(JSONValue.int) ?? .null
        }
        return values
    }

    /// 72 → entier, 62,5 → décimal (le champ est numérique).
    static func number(_ value: Double) -> JSONValue {
        value.rounded() == value && abs(value) < 1e9 ? .int(Int(value)) : .double(value)
    }
}

/// Saisie du score dans la fenêtre « Modifier le score ».
public enum ScoreInput {
    public static let range: ClosedRange<Double> = 0...100

    /// « 72 », « 62,5 », « 62.5 » → la valeur ; nil si illisible ou hors de 0 à 100.
    public static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, range.contains(value) else { return nil }
        return (value * 10).rounded() / 10
    }
}
