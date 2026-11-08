import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Prévient Claude tout de suite quand Yves envoie une « Note pour Claude » (demande d'Yves du 08/11/2026 : « en temps
/// réel, comme un hook », plutôt qu'une vérification toutes les 10 minutes). L'app appelle l'adresse de déclenchement
/// (« Fire URL ») d'une tâche planifiée Claude ; la tâche lit la note dans Pipedrive et met à jour l'analyse de
/// l'affaire. L'adresse et le jeton sont collés par Yves dans les Réglages (jeton dans le trousseau, jamais dans le code).
public struct ClaudeTrigger: Sendable {
    public enum TriggerError: Error, Equatable, LocalizedError, Sendable {
        case invalidURL
        case missingToken
        case unauthorized
        case rateLimited
        case rejected(status: Int, message: String?)

        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Adresse de déclenchement Claude invalide (elle commence par https://api.anthropic.com/v1/claude_code/routines/ et finit par /fire)."
            case .missingToken:
                return "Aucun jeton Claude enregistré."
            case .unauthorized:
                return "Jeton Claude refusé : générez-en un nouveau dans la tâche Claude et collez-le dans Réglages."
            case .rateLimited:
                return "Trop de notes pour Claude en une heure : elle sera lue à la prochaine analyse (5h17 ou 13h17)."
            case .rejected(let status, let message):
                return message.map { "Claude : \($0)" } ?? "Claude n'a pas pu être prévenu (code \(status))."
            }
        }
    }

    /// Version d'API exigée par l'adresse de déclenchement.
    static let apiVersion = "2026-10-21"

    public let fireURL: URL
    let token: String
    let transport: any HTTPTransport

    public init(fireURL: String, token: String, transport: any HTTPTransport = URLSessionTransport()) throws {
        guard let url = Self.validURL(fireURL) else { throw TriggerError.invalidURL }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw TriggerError.missingToken }
        self.fireURL = url
        self.token = token
        self.transport = transport
    }

    /// Adresse de déclenchement d'une tâche Claude : https://api.anthropic.com/v1/claude_code/routines/trig_…/fire.
    public static func validURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^https://api\.anthropic\.com/v1/claude_code/routines/trig_[A-Za-z0-9]+/fire$"#,
                            options: .regularExpression) != nil else { return nil }
        return URL(string: trimmed)
    }

    /// Texte transmis à la tâche : seulement les identifiants (la tâche relit la note dans Pipedrive).
    public static func payload(noteID: Int, dealID: Int?) -> String {
        "note_id=\(noteID) deal_id=\(dealID.map(String.init) ?? "aucune")"
    }

    /// Lance la tâche Claude ; renvoie l'adresse de la session créée si Claude la donne.
    @discardableResult
    public func fire(text: String) async throws -> String? {
        var request = URLRequest(url: fireURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
        request.timeoutInterval = 30
        let (data, response) = try await transport.send(request)
        let json = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
        switch response.statusCode {
        case 200..<300:
            return json["claude_code_session_url"].stringValue
        case 401:
            throw TriggerError.unauthorized
        case 429:
            throw TriggerError.rateLimited
        default:
            throw TriggerError.rejected(status: response.statusCode, message: json["error"]["message"].stringValue)
        }
    }
}
