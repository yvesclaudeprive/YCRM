import Foundation

public enum PipedriveError: Error, Equatable, LocalizedError, Sendable {
    case missingToken
    case invalidDomain
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case server(status: Int, message: String?)
    case invalidResponse
    case validation(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Aucun jeton API enregistré."
        case .invalidDomain:
            return "Adresse Pipedrive invalide (exemple : yateo)."
        case .unauthorized:
            return "Jeton API refusé par Pipedrive. Vérifiez-le dans Réglages."
        case .forbidden:
            return "Pipedrive refuse cette action pour votre compte."
        case .notFound:
            return "Élément introuvable dans Pipedrive."
        case .rateLimited:
            return "Trop de requêtes vers Pipedrive. Réessayez dans une minute."
        case .server(let status, let message):
            return message.map { "Pipedrive : \($0)" } ?? "Erreur Pipedrive (code \(status))."
        case .invalidResponse:
            return "Réponse inattendue de Pipedrive."
        case .validation(let message):
            return message
        }
    }
}
