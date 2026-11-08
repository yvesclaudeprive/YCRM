import Foundation

/// Définition d'un champ Pipedrive (ici : champs des affaires, pour retrouver « Score priorisation »).
public struct FieldDefinition: Hashable, Sendable, Identifiable {
    public let code: String
    public let name: String
    public let type: String
    public let isCustom: Bool

    public var id: String { code }

    public init(code: String, name: String, type: String, isCustom: Bool) {
        self.code = code
        self.name = name
        self.type = type
        self.isCustom = isCustom
    }

    /// Format API v2 (`/api/v2/dealFields`).
    init?(v2 json: JSONValue) {
        guard let code = json["field_code"].stringValue, let type = json["field_type"].stringValue else { return nil }
        self.init(code: code, name: json["field_name"].stringValue ?? code, type: type,
                  isCustom: json["is_custom_field"].boolValue ?? Self.looksLikeCustomKey(code))
    }

    /// Ancien format v1 (`/api/v1/dealFields`), en secours.
    init?(v1 json: JSONValue) {
        guard let code = json["key"].stringValue, let type = json["field_type"].stringValue else { return nil }
        self.init(code: code, name: json["name"].stringValue ?? code, type: type, isCustom: Self.looksLikeCustomKey(code))
    }

    /// Les champs personnalisés Pipedrive ont une clé de 40 caractères hexadécimaux.
    static func looksLikeCustomKey(_ code: String) -> Bool {
        code.count == 40 && code.allSatisfy { $0.isHexDigit }
    }
}

/// Utilisateur Pipedrive (le titulaire du jeton : `/api/v1/users/me`).
public struct PipedriveUser: Hashable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let email: String?
    public let isActive: Bool

    public init(id: Int, name: String, email: String?, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.email = email
        self.isActive = isActive
    }

    init?(json: JSONValue) {
        guard let id = json["id"].intValue else { return nil }
        self.init(id: id, name: json["name"].stringValue ?? "Utilisateur #\(id)", email: json["email"].stringValue,
                  isActive: json["active_flag"].boolValue ?? true)
    }
}

/// Comparaison de libellés sans tenir compte des accents, de la casse ni des espaces en trop.
enum Label {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func matches(_ a: String, _ b: String) -> Bool {
        normalized(a) == normalized(b)
    }
}
