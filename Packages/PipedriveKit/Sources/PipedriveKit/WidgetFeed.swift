import Foundation

/// Liens « ycrm:// » du widget de l'écran de gauche vers l'app (demande d'Yves du 25/11/2026) :
/// la barre de recherche ouvre la recherche de l'app, une alerte ouvre YCRM sur sa carte (et non plus Pipedrive :
/// retour d'Yves du 25/11/2026).
public enum YCRMLink {
    public static let scheme = "ycrm"

    public enum Destination: Equatable, Sendable {
        /// La liste des alertes.
        case home
        /// La liste, champ de recherche actif (clavier ouvert).
        case search
        /// La liste, sur la carte de cette alerte (identifiant de l'activité Pipedrive).
        case alert(id: Int)
    }

    public static var home: URL { link(host: "home", items: []) }
    public static var search: URL { link(host: "search", items: []) }

    public static func alert(id: Int) -> URL {
        link(host: "alert", items: [URLQueryItem(name: "id", value: String(id))])
    }

    /// Ce que demande un lien « ycrm:// » (nil pour un autre lien).
    public static func destination(of url: URL) -> Destination? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        func number(_ name: String) -> Int? {
            components?.queryItems?.first { $0.name == name }?.value.flatMap { Int($0) }
        }
        switch components?.host?.lowercased() {
        case "search":
            return .search
        case "alert":
            return number("id").map { .alert(id: $0) } ?? .home
        default:
            // Y compris « ycrm://open?… » des premiers widgets (fiche Pipedrive) : la liste.
            return .home
        }
    }

    private static func link(host: String, items: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = items.isEmpty ? nil : items
        return components.url ?? URL(fileURLWithPath: "/")
    }
}

/// Une alerte affichée dans le widget : de quoi dessiner la ligne et ouvrir la fiche, sans rien d'autre.
public struct WidgetAlert: Codable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let company: String
    public let person: String?
    /// Texte de l'activité.
    public let text: String
    /// « Score priorisation » de l'affaire.
    public let score: Double?
    /// Échéance telle que Pipedrive la donne (UTC).
    public let dueDate: String?
    public let dueTime: String?
    public let dealID: Int?
    public let personID: Int?
    public let orgID: Int?

    public init(id: Int, company: String, person: String?, text: String, score: Double?, dueDate: String?,
                dueTime: String?, dealID: Int?, personID: Int?, orgID: Int?) {
        self.id = id
        self.company = company
        self.person = person
        self.text = text
        self.score = score
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.dealID = dealID
        self.personID = personID
        self.orgID = orgID
    }

    public init(item: ActivityItem) {
        self.init(id: item.id, company: item.clientName, person: item.person?.name,
                  text: item.activity.subject.trimmingCharacters(in: .whitespacesAndNewlines),
                  score: item.score, dueDate: item.activity.dueDate, dueTime: item.activity.dueTime,
                  dealID: item.activity.dealID, personID: item.person?.id ?? item.activity.personID, orgID: item.orgID)
    }

    /// Lien vers l'app, qui ouvre la liste sur la carte de l'alerte.
    public var link: URL { YCRMLink.alert(id: id) }

    /// « 62,5 » ; nil sans score.
    public var scoreText: String? { score.map { FrenchFormat.number($0, maxDecimals: 1) } }

    private var activity: Activity {
        Activity(id: id, subject: text, type: "", dueDate: dueDate, dueTime: (dueTime ?? "").isEmpty ? nil : dueTime,
                 dealID: dealID, personID: personID, orgID: orgID, done: false)
    }

    /// En retard, aujourd'hui ou à venir (couleur de la date, comme dans l'app).
    public func status(now: Date = Date(), timeZone: TimeZone) -> DateStatus? {
        activity.dateStatus(now: now, timeZone: timeZone)
    }

    /// Date courte, heure de Paris : « 14:30 » ou « Aujourd'hui » le jour même, sinon « 18 nov. »
    /// (« 1er déc. », « 18 nov. 2025 » une autre année).
    public func shortDate(now: Date = Date(), timeZone: TimeZone) -> String {
        let activity = self.activity
        guard let day = activity.localDay(timeZone: timeZone), let parts = FrenchFormat.dayParts(day) else {
            return "Sans date"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if activity.dateStatus(now: now, timeZone: timeZone) == .today {
            guard let instant = activity.dueInstant else { return "Aujourd'hui" }
            let time = calendar.dateComponents([.hour, .minute], from: instant)
            return String(format: "%02ld:%02ld", time.hour ?? 0, time.minute ?? 0)
        }
        let months = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]
        let month = (1...12).contains(parts.month) ? months[parts.month - 1] : String(parts.month)
        let text = "\(parts.day == 1 ? "1er" : String(parts.day)) \(month)"
        return parts.year == calendar.component(.year, from: now) ? text : "\(text) \(parts.year)"
    }
}

/// Ce que montre le widget : les premières alertes de la liste (même ordre que l'app).
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public let alerts: [WidgetAlert]
    /// Nombre d'activités en retard ou du jour (toutes, pas seulement celles affichées).
    public let dueCount: Int
    public let updatedAt: Date

    public init(alerts: [WidgetAlert], dueCount: Int, updatedAt: Date) {
        self.alerts = alerts
        self.dueCount = dueCount
        self.updatedAt = updatedAt
    }

    /// « Mis à jour à 14:20 » (heure de Paris).
    public func updatedText(timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = calendar.dateComponents([.hour, .minute], from: updatedAt)
        return String(format: "Mis à jour à %02ld:%02ld", time.hour ?? 0, time.minute ?? 0)
    }
}

/// Chargement du widget : mes activités ouvertes, dans l'ordre de l'app (en retard et du jour d'abord, par score).
/// Seules les activités jusqu'à aujourd'hui sont lues, sauf s'il y en a moins que d'alertes à afficher.
public struct WidgetFeedLoader: Sendable {
    /// Nombre d'alertes gardées : le widget très haut d'iOS 27 en affiche ≈ 12, et le widget « suite » la suite.
    public static let maxAlerts = 30

    let client: PipedriveClient

    public init(client: PipedriveClient) {
        self.client = client
    }

    public func load(ownerID: Int?, limit: Int = maxAlerts, timeZone: TimeZone,
                     now: Date = Date()) async throws -> WidgetSnapshot {
        let owner: Int
        if let ownerID {
            owner = ownerID
        } else {
            owner = try await client.currentUser().id
        }
        let loader = ActivityFeedLoader(client: client)
        let due = try await loader.load(ownerIDs: [owner], filter: .untilToday(now: now, timeZone: timeZone),
                                        timeZone: timeZone, now: now)
        var items = due
        if due.count < limit {
            items = try await loader.load(ownerIDs: [owner], filter: ActivityDateFilter(from: nil, to: nil),
                                          timeZone: timeZone, now: now)
        }
        return Self.snapshot(items: items, dueCount: due.count, limit: limit, now: now)
    }

    public static func snapshot(items: [ActivityItem], dueCount: Int, limit: Int = maxAlerts, now: Date) -> WidgetSnapshot {
        WidgetSnapshot(alerts: items.prefix(limit).map(WidgetAlert.init(item:)), dueCount: dueCount, updatedAt: now)
    }
}
