import Foundation

/// Étiquettes affichées sur une fiche (demande d'Yves du 08/11/2026) :
/// - « Devis envoyé » : une activité terminée « Devis envoyé » (ou dont le texte dit qu'un devis a été envoyé)
///   existe sur l'affaire, et l'affaire est toujours en cours (pas gagnée ni perdue) ;
/// - « 1er call à faire » : aucun échange de vive voix connu avec le contact (appel décroché, « Call effectué »,
///   rendez-vous, enregistrement Leexi). Répondeurs, appels manqués, SMS et e-mails ne comptent pas.
public struct LeadTags: Hashable, Sendable {
    /// Jour (AAAA-MM-JJ, heure de Paris) du dernier « Devis envoyé », s'il y en a un.
    public let quoteSentDay: String?
    public let firstCallToDo: Bool

    public init(quoteSentDay: String?, firstCallToDo: Bool) {
        self.quoteSentDay = quoteSentDay
        self.firstCallToDo = firstCallToDo
    }

    public static let none = LeadTags(quoteSentDay: nil, firstCallToDo: false)

    public var isEmpty: Bool { quoteSentDay == nil && !firstCallToDo }

    /// « Devis envoyé · aujourd'hui », « Devis envoyé · hier », « Devis envoyé · il y a 5 j ».
    public func quoteSentLabel(now: Date = Date(), timeZone: TimeZone) -> String? {
        guard let quoteSentDay else { return nil }
        guard let days = Self.daysBetween(quoteSentDay, FrenchFormat.apiDay(from: now, timeZone: timeZone)) else {
            return "Devis envoyé"
        }
        switch days {
        case ..<1: return "Devis envoyé · aujourd'hui"
        case 1: return "Devis envoyé · hier"
        default: return "Devis envoyé · il y a \(days) j"
        }
    }

    static func daysBetween(_ from: String, _ to: String) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: String(from.prefix(10))), let end = formatter.date(from: String(to.prefix(10))) else {
            return nil
        }
        return calendar.dateComponents([.day], from: start, to: end).day
    }
}

/// Règles de lecture des activités Pipedrive pour les étiquettes.
public enum LeadTagRules {
    /// Échange de vive voix : appel Aircall décroché, « Call effectué », appel ou rendez-vous Pipedrive, événement d'agenda.
    public static func isConversation(_ activity: Activity, typeNames: [String: String]) -> Bool {
        guard activity.done else { return false }
        let key = activity.type.lowercased()
        let name = Label.normalized(typeNames[activity.type] ?? activity.type)
        let notReached = ["unanswer", "missed", "voicemail", "repondeur", "rpondeur", "sms", "msg"]
        if notReached.contains(where: { key.contains($0) || name.contains($0) }) { return false }
        if key.contains("_answered") || name.contains("answered") { return true }
        if ["call", "meeting", "google_agenda"].contains(key) { return true }
        if Label.matches(name, DebriefTemplate.typeName) || key.hasPrefix("call_effectu") { return true }
        return ["reunion", "rendez-vous", "rdv", "visio", "meeting"].contains { name.contains($0) }
    }

    /// Devis envoyé : type « Devis envoyé », ou texte qui parle d'un devis envoyé (« devis SEO envoyé », « renvoyer le devis »).
    public static func isQuoteSent(_ activity: Activity, typeNames: [String: String]) -> Bool {
        guard activity.done else { return false }
        let name = typeNames[activity.type] ?? activity.type
        if Label.matches(name, "Devis envoyé") || activity.type.lowercased().hasPrefix("devis_envoy") { return true }
        let subject = Label.normalized(activity.subject)
        return subject.contains("devis") && subject.range(of: #"\b(r?envoy|envoi)"#, options: .regularExpression) != nil
    }
}

/// Calcule les étiquettes d'une fiche à partir de Pipedrive (1 à 4 requêtes, faites quand la carte apparaît).
public struct LeadTagsLoader: Sendable {
    let client: PipedriveClient

    public init(client: PipedriveClient) {
        self.client = client
    }

    public func load(for item: ActivityItem, typeNames: [String: String], timeZone: TimeZone) async throws -> LeadTags {
        let dealID = item.activity.dealID
        let personID = item.person?.id ?? item.activity.personID
        guard dealID != nil || personID != nil else { return .none }
        // Affaire gagnée ou perdue : pas d'étiquette (client signé, ou affaire close).
        if let deal = item.deal, !deal.isOpen { return .none }

        var dealDone: [Activity] = []
        if let dealID {
            dealDone = try await client.activities(filter: "deal_id", id: dealID, limit: 200, done: true)
        }
        var spoke = dealDone.contains { LeadTagRules.isConversation($0, typeNames: typeNames) }
        var personDone: [Activity] = []
        if !spoke, let personID {
            // Les journaux Aircall sont toujours liés à la personne, pas toujours à l'affaire.
            personDone = try await client.activities(filter: "person_id", id: personID, limit: 200, done: true)
            spoke = personDone.contains { LeadTagRules.isConversation($0, typeNames: typeNames) }
        }
        if !spoke, let dealID {
            spoke = try await client.notes(filter: "deal_id", id: dealID, limit: 50).contains(where: \.isLeexi)
        }
        if !spoke, let personID {
            spoke = try await client.notes(filter: "person_id", id: personID, limit: 50).contains(where: \.isLeexi)
        }

        // Devis : ceux de l'affaire ; sans affaire, ceux de la personne.
        let quoteSource = dealID != nil ? dealDone : personDone
        let quoteDay = quoteSource
            .filter { LeadTagRules.isQuoteSent($0, typeNames: typeNames) }
            .compactMap { $0.localDay(timeZone: timeZone) }
            .max()
        return LeadTags(quoteSentDay: quoteDay, firstCallToDo: !spoke)
    }
}
