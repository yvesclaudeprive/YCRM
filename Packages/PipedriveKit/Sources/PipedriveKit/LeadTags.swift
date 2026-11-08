import Foundation

/// Étiquettes affichées sur une fiche (demande d'Yves du 08/11/2026) :
/// - « Devis envoyé » : une activité terminée « Devis envoyé » (ou dont le texte dit qu'un devis a été envoyé)
///   existe sur l'affaire, et l'affaire est toujours en cours (pas gagnée ni perdue) ;
/// - « 1er call à faire » : aucun échange de vive voix connu avec le contact (appel décroché, « Call effectué »,
///   rendez-vous, enregistrement Leexi). Répondeurs, appels manqués, SMS et e-mails ne comptent pas.
public struct LeadTags: Hashable, Sendable {
    /// Devis envoyés sur l'affaire (activités terminées), le plus récent d'abord : détail au toucher de l'étiquette.
    public let quotes: [QuoteSent]
    public let firstCallToDo: Bool

    public init(quotes: [QuoteSent], firstCallToDo: Bool) {
        self.quotes = quotes
        self.firstCallToDo = firstCallToDo
    }

    /// Raccourci (tests) : un seul devis envoyé ce jour-là.
    public init(quoteSentDay: String?, firstCallToDo: Bool) {
        self.init(quotes: quoteSentDay.map { [QuoteSent(id: 0, subject: "Devis envoyé", day: $0, dateText: $0, note: nil)] } ?? [],
                  firstCallToDo: firstCallToDo)
    }

    public static let none = LeadTags(quotes: [], firstCallToDo: false)

    /// Jour (AAAA-MM-JJ, heure de Paris) du dernier « Devis envoyé », s'il y en a un.
    public var quoteSentDay: String? { quotes.first?.day }

    public var isEmpty: Bool { quoteSentDay == nil && !firstCallToDo }

    /// « Devis envoyé · aujourd'hui », « Devis envoyé · hier », « Devis envoyé · il y a 5 j ».
    public func quoteSentLabel(now: Date = Date(), timeZone: TimeZone) -> String? {
        guard let latest = quotes.first else { return nil }
        guard let ago = latest.agoText(now: now, timeZone: timeZone) else { return "Devis envoyé" }
        return "Devis envoyé · \(ago)"
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

/// Un devis envoyé (activité terminée de l'affaire), pour la fenêtre de détail.
public struct QuoteSent: Hashable, Sendable, Identifiable {
    public let id: Int
    /// Texte de l'activité (« Devis SEO envoyé »).
    public let subject: String
    /// Jour à l'heure de Paris (AAAA-MM-JJ).
    public let day: String
    /// Date affichée (« 3 novembre à 14:30 »).
    public let dateText: String
    /// Note de l'activité en texte simple, s'il y en a une.
    public let note: String?

    public init(id: Int, subject: String, day: String, dateText: String, note: String?) {
        self.id = id
        self.subject = subject
        self.day = day
        self.dateText = dateText
        self.note = note
    }

    /// « aujourd'hui », « hier », « il y a 5 j ».
    public func agoText(now: Date = Date(), timeZone: TimeZone) -> String? {
        guard let days = LeadTags.daysBetween(day, FrenchFormat.apiDay(from: now, timeZone: timeZone)) else { return nil }
        switch days {
        case ..<1: return "aujourd'hui"
        case 1: return "hier"
        default: return "il y a \(days) j"
        }
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

    public func load(for item: ActivityItem, typeNames: [String: String], timeZone: TimeZone,
                     now: Date = Date()) async throws -> LeadTags {
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
        let quotes = quoteSource
            .filter { LeadTagRules.isQuoteSent($0, typeNames: typeNames) }
            .compactMap { activity -> QuoteSent? in
                guard let day = activity.localDay(timeZone: timeZone) else { return nil }
                let note = activity.note.map(PlainText.from(html:))?.trimmingCharacters(in: .whitespacesAndNewlines)
                return QuoteSent(id: activity.id, subject: activity.subject.isEmpty ? "Devis envoyé" : activity.subject,
                                 day: day, dateText: activity.displayDate(now: now),
                                 note: (note?.isEmpty ?? true) ? nil : note)
            }
            .sorted { $0.day != $1.day ? $0.day > $1.day : $0.id > $1.id }
        return LeadTags(quotes: quotes, firstCallToDo: !spoke)
    }
}
