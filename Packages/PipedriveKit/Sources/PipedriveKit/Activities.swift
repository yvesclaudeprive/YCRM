import Foundation

/// Activité Pipedrive (« alerte » pour Yves), format API v2.
public struct Activity: Hashable, Sendable, Identifiable {
    public let id: Int
    public let subject: String
    public let type: String
    /// Date d'échéance telle que renvoyée par Pipedrive (AAAA-MM-JJ, en UTC si une heure est renseignée).
    public let dueDate: String?
    /// Heure d'échéance (HH:MM, UTC) ou nil.
    public let dueTime: String?
    public let dealID: Int?
    public let personID: Int?
    public let orgID: Int?
    public let done: Bool
    /// Note (commentaire) de l'activité, en HTML comme dans Pipedrive.
    public let note: String?
    /// Utilisateur Pipedrive à qui l'activité est attribuée.
    public let ownerID: Int?
    /// Création dans Pipedrive (UTC, « 2026-07-02T10:10:54Z ») : moment réel d'une activité notée sans heure.
    public let addTime: String?

    public init(id: Int, subject: String, type: String, dueDate: String?, dueTime: String?,
                dealID: Int?, personID: Int?, orgID: Int?, done: Bool, note: String? = nil, ownerID: Int? = nil,
                addTime: String? = nil) {
        self.id = id
        self.subject = subject
        self.type = type
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.dealID = dealID
        self.personID = personID
        self.orgID = orgID
        self.done = done
        self.note = note
        self.ownerID = ownerID
        self.addTime = addTime
    }

    init?(json: JSONValue) {
        guard let id = json["id"].intValue else { return nil }
        let participants = json["participants"].arrayValue ?? []
        let primary = participants.first(where: { $0["primary"].boolValue == true }) ?? participants.first
        let primaryParticipant = primary?["person_id"].intValue
        let time = json["due_time"].stringValue.flatMap { $0.isEmpty ? nil : String($0.prefix(5)) }
        self.init(
            id: id,
            subject: json["subject"].stringValue ?? "",
            type: json["type"].stringValue ?? "",
            dueDate: json["due_date"].stringValue,
            dueTime: time,
            dealID: json["deal_id"].intValue,
            personID: json["person_id"].intValue ?? primaryParticipant,
            orgID: json["org_id"].intValue,
            done: json["done"].boolValue ?? false,
            note: json["note"].stringValue,
            ownerID: json["owner_id"].intValue ?? json["user_id"].intValue,
            addTime: json["add_time"].stringValue
        )
    }

    /// Instant UTC de l'échéance, si une heure est renseignée.
    public var dueInstant: Date? {
        guard let dueDate, let dueTime else { return nil }
        return FrenchFormat.parseInstant("\(dueDate)T\(dueTime):00Z")
    }

    /// Jour de l'activité à l'heure de Paris (AAAA-MM-JJ), utilisé pour le filtre de dates.
    public func localDay(timeZone: TimeZone) -> String? {
        if let instant = dueInstant { return FrenchFormat.apiDay(from: instant, timeZone: timeZone) }
        return dueDate.map { String($0.prefix(10)) }
    }

    /// En retard, aujourd'hui ou à venir (couleur de la date : rouge, orange, vert).
    public func dateStatus(now: Date = Date(), timeZone: TimeZone) -> DateStatus? {
        guard let day = localDay(timeZone: timeZone) else { return nil }
        let today = FrenchFormat.apiDay(from: now, timeZone: timeZone)
        if day < today { return .overdue }
        if day == today { return .today }
        return .upcoming
    }

    /// Date affichée : « 7 novembre à 14:30 » (heure de Paris), « 12 décembre 2025 » si autre année.
    public var displayDate: String { displayDate(now: Date()) }

    public func displayDate(now: Date, weekday: Bool = false) -> String {
        if let dueDate, let dueTime {
            return FrenchFormat.longDate(fromAPI: "\(dueDate)T\(dueTime):00Z", now: now, weekday: weekday)
        }
        return dueDate.map { FrenchFormat.longDate(fromAPI: $0, now: now, weekday: weekday) } ?? "Sans date"
    }
}

/// Numéro de téléphone ou adresse e-mail d'un contact.
public struct ContactPoint: Hashable, Sendable {
    public let value: String
    public let label: String?
    public let primary: Bool

    public init(value: String, label: String?, primary: Bool) {
        self.value = value
        self.label = label
        self.primary = primary
    }

    init?(json: JSONValue) {
        guard let value = json["value"].stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        self.init(value: value, label: json["label"].stringValue, primary: json["primary"].boolValue ?? false)
    }

    /// Libellé lisible : « Mobile », « Travail »…
    public var displayLabel: String {
        switch (label ?? "").lowercased() {
        case "mobile": return "Mobile"
        case "work": return "Travail"
        case "home": return "Domicile"
        case "other": return "Autre"
        case "": return primary ? "Principal" : "Autre"
        default: return label ?? "Autre"
        }
    }
}

/// Personne à contacter (API v2 `/persons`).
public struct PersonContact: Hashable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let phones: [ContactPoint]
    public let emails: [ContactPoint]
    public let orgID: Int?

    public init(id: Int, name: String, phones: [ContactPoint], emails: [ContactPoint], orgID: Int?) {
        self.id = id
        self.name = name
        self.phones = phones
        self.emails = emails
        self.orgID = orgID
    }

    init?(json: JSONValue) {
        guard let id = json["id"].intValue else { return nil }
        func points(_ key: String) -> [ContactPoint] {
            let all = (json[key].arrayValue ?? []).compactMap(ContactPoint.init(json:))
            var seen = Set<String>()
            // Principal d'abord, doublons retirés.
            return (all.filter(\.primary) + all.filter { !$0.primary }).filter { seen.insert($0.value.lowercased()).inserted }
        }
        self.init(id: id, name: json["name"].stringValue ?? "Contact #\(id)", phones: points("phones"),
                  emails: points("emails"), orgID: json["org_id"].intValue)
    }

    /// Numéros appelables (format international), principal d'abord.
    public var callableNumbers: [(label: String, e164: String)] {
        phones.compactMap { point in
            PhoneNumber.e164(point.value).map { (label: point.displayLabel, e164: $0) }
        }
    }
}

/// Affaire réduite à ce dont la liste a besoin.
public struct DealSummary: Hashable, Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let orgID: Int?
    public let personID: Int?
    public let score: Double?
    /// « open », « won », « lost » (nil si inconnu).
    public let status: String?
    /// Date de gain (« Gagnée »), format API.
    public let wonTime: String?
    /// Champ d'affaire « Contrat signé le » (AAAA-MM-JJ), s'il existe dans le compte (rempli par ex. depuis l'yntranet).
    public let signedDate: String?
    /// Champ d'affaire « Devis en attente » : analyse des devis écrite par Claude deux fois par jour (`QuoteAnalysis`).
    public let quoteAnalysis: String?
    /// Création de l'affaire (format API) : borne de l'historique de l'affaire (`HistoryScope`).
    public let addTime: String?

    public init(id: Int, title: String, orgID: Int?, personID: Int?, score: Double?, status: String? = nil,
                wonTime: String? = nil, signedDate: String? = nil, quoteAnalysis: String? = nil, addTime: String? = nil) {
        self.id = id
        self.title = title
        self.orgID = orgID
        self.personID = personID
        self.score = score
        self.status = status
        self.wonTime = wonTime
        self.signedDate = signedDate
        self.quoteAnalysis = quoteAnalysis
        self.addTime = addTime
    }

    /// Date de création de l'affaire.
    public var createdAt: Date? { addTime.flatMap(FrenchFormat.parseInstant) }

    /// Affaire en cours (ni gagnée ni perdue) ; vrai si le statut est inconnu.
    public var isOpen: Bool { status == nil || status == "open" }

    init?(json: JSONValue, scoreCode: String?, signedCode: String? = nil, analysisCode: String? = nil) {
        guard let id = json["id"].intValue else { return nil }
        var score: Double?
        if let scoreCode {
            let raw = json["custom_fields"][scoreCode]
            score = raw.isNull ? json[scoreCode].doubleValue : (raw.doubleValue ?? raw["value"].doubleValue)
        }
        var signed: String?
        if let signedCode {
            let raw = json["custom_fields"][signedCode]
            signed = (raw.isNull ? json[signedCode].stringValue : (raw.stringValue ?? raw["value"].stringValue))
                .flatMap { $0.isEmpty ? nil : $0 }
        }
        var analysis: String?
        if let analysisCode {
            let raw = json["custom_fields"][analysisCode]
            analysis = (raw.isNull ? json[analysisCode].stringValue : (raw.stringValue ?? raw["value"].stringValue))
                .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }
        self.init(id: id, title: json["title"].stringValue ?? "Affaire #\(id)", orgID: json["org_id"].intValue,
                  personID: json["person_id"].intValue, score: score, status: json["status"].stringValue,
                  wonTime: json["won_time"].stringValue, signedDate: signed, quoteAnalysis: analysis,
                  addTime: json["add_time"].stringValue)
    }
}

/// Type d'activité (API v1 `/activityTypes`) : sert à créer « Répondeur ON/OFF »…
public struct ActivityType: Hashable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let key: String
    public let isActive: Bool

    public init(id: Int, name: String, key: String, isActive: Bool) {
        self.id = id
        self.name = name
        self.key = key
        self.isActive = isActive
    }

    init?(json: JSONValue) {
        guard let id = json["id"].intValue, let key = json["key_string"].stringValue else { return nil }
        self.init(id: id, name: json["name"].stringValue ?? key, key: key, isActive: json["active_flag"].boolValue ?? true)
    }

    /// Type actif portant ce nom (accents et casse ignorés).
    public static func named(_ name: String, in types: [ActivityType]) -> ActivityType? {
        types.first { $0.isActive && Label.matches($0.name, name) } ?? types.first { Label.matches($0.name, name) }
    }
}

/// Une ligne de la liste : l'activité et tout ce qui est affiché ou utilisé par les boutons.
public struct ActivityItem: Hashable, Sendable, Identifiable {
    public let activity: Activity
    public let organizationName: String?
    public let person: PersonContact?
    public let deal: DealSummary?

    public var id: Int { activity.id }
    public var score: Double? { deal?.score }
    public var orgID: Int? { activity.orgID ?? deal?.orgID ?? person?.orgID }

    public init(activity: Activity, organizationName: String?, person: PersonContact?, deal: DealSummary?) {
        self.activity = activity
        self.organizationName = organizationName
        self.person = person
        self.deal = deal
    }

    /// La même ligne avec l'affaire relue dans Pipedrive.
    public func withDeal(_ deal: DealSummary?) -> ActivityItem {
        ActivityItem(activity: activity, organizationName: organizationName, person: person, deal: deal)
    }

    /// Nom utilisé dans « [NOMDUCLIENT] » : la société, sinon la personne, sinon l'affaire.
    public var clientName: String {
        organizationName ?? person?.name ?? deal?.title ?? "Sans société"
    }

    /// Tri par défaut : score de priorisation décroissant (sans score en bas), puis date, puis heure.
    /// À venir (échéance après aujourd'hui, heure de Paris) ; les activités sans date comptent comme à venir.
    public func isUpcoming(today: String, timeZone: TimeZone) -> Bool {
        guard let day = activity.localDay(timeZone: timeZone) else { return true }
        return day > today
    }

    /// Ordre de la liste (demande d'Yves du 08/11/2026) : d'abord les activités en retard et du jour,
    /// puis celles à venir ; dans chaque groupe, par score (sans score à la fin), puis par date.
    public static func feedOrder(_ items: [ActivityItem], today: String, timeZone: TimeZone) -> [ActivityItem] {
        let upcoming = items.filter { $0.isUpcoming(today: today, timeZone: timeZone) }
        let due = items.filter { !$0.isUpcoming(today: today, timeZone: timeZone) }
        return due.sorted(by: prioritySort) + upcoming.sorted(by: prioritySort)
    }

    public static func prioritySort(_ lhs: ActivityItem, _ rhs: ActivityItem) -> Bool {
        switch (lhs.score, rhs.score) {
        case let (l?, r?) where l != r: return l > r
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        let lDate = (lhs.activity.dueDate ?? "9999-99-99") + (lhs.activity.dueTime ?? "99:99")
        let rDate = (rhs.activity.dueDate ?? "9999-99-99") + (rhs.activity.dueTime ?? "99:99")
        if lDate != rDate { return lDate < rDate }
        return lhs.activity.id < rhs.activity.id
    }
}

public enum DateStatus: Sendable, Equatable {
    case overdue, today, upcoming
}

/// Filtre « Score » (demande d'Yves du 08/11/2026) : les activités sans « Score priorisation »
/// (affaire non notée ou pas d'affaire) sont affichées après les autres, ce filtre permet de les isoler.
public enum ScoreFilter: String, CaseIterable, Sendable, Identifiable {
    case all, scored, unscored

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "Tous"
        case .scored: return "Avec score"
        case .unscored: return "Sans score"
        }
    }

    public func matches(_ item: ActivityItem) -> Bool {
        switch self {
        case .all: return true
        case .scored: return item.score != nil
        case .unscored: return item.score == nil
        }
    }
}

/// Raccourcis du filtre « Date ».
public enum DatePreset: String, CaseIterable, Sendable, Identifiable {
    case all, untilToday, today, overdue, upcoming, next7Days, next30Days, custom

    /// Par défaut (demande d'Yves du 08/11/2026) : toutes les activités non terminées,
    /// les retards et celles du jour d'abord, puis celles à venir.
    public static let defaultPreset = DatePreset.all

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .untilToday: return "Jusqu'à aujourd'hui"
        case .today: return "Aujourd'hui"
        case .overdue: return "En retard"
        case .upcoming: return "À venir (à partir de demain)"
        case .next7Days: return "Aujourd'hui + 7 jours"
        case .next30Days: return "Aujourd'hui + 30 jours"
        case .all: return "Toutes (retard et jour d'abord, puis à venir)"
        case .custom: return "Période personnalisée"
        }
    }

    /// Bornes du filtre, recalculées à chaque chargement (« aujourd'hui » avance avec la date).
    public func filter(now: Date = Date(), timeZone: TimeZone, customFrom: Date? = nil, customTo: Date? = nil) -> ActivityDateFilter {
        func day(_ offset: Int) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            return FrenchFormat.apiDay(from: date, timeZone: timeZone)
        }
        switch self {
        case .untilToday: return ActivityDateFilter(from: nil, to: day(0))
        case .today: return ActivityDateFilter(from: day(0), to: day(0))
        case .overdue: return ActivityDateFilter(from: nil, to: day(-1))
        case .upcoming: return ActivityDateFilter(from: day(1), to: nil)
        case .next7Days: return ActivityDateFilter(from: day(0), to: day(7))
        case .next30Days: return ActivityDateFilter(from: day(0), to: day(30))
        case .all: return ActivityDateFilter(from: nil, to: nil)
        case .custom:
            var from = customFrom.map { FrenchFormat.apiDay(from: $0, timeZone: timeZone) }
            var to = customTo.map { FrenchFormat.apiDay(from: $0, timeZone: timeZone) }
            if let start = from, let end = to, start > end { (from, to) = (end, start) }
            return ActivityDateFilter(from: from, to: to)
        }
    }
}

/// Tranches de 20 du score : bleu (< 20, peu important) → rouge (≥ 60, important, demande d'Yves du 07/11/2026).
public enum ScoreBand: Int, Sendable, CaseIterable {
    case veryLow, low, medium, high, veryHigh

    public init(score: Double) {
        switch score {
        case ..<20: self = .veryLow
        case ..<40: self = .low
        case ..<60: self = .medium
        case ..<80: self = .high
        default: self = .veryHigh
        }
    }
}

/// Filtre de dates (jours de Paris, bornes incluses, `nil` = sans limite).
public struct ActivityDateFilter: Hashable, Sendable {
    public var from: String?
    public var to: String?

    public init(from: String?, to: String?) {
        self.from = from
        self.to = to
    }

    /// Par défaut : toutes les activités jusqu'à aujourd'hui inclus.
    public static func untilToday(now: Date = Date(), timeZone: TimeZone) -> ActivityDateFilter {
        ActivityDateFilter(from: nil, to: FrenchFormat.apiDay(from: now, timeZone: timeZone))
    }

    public func contains(day: String?) -> Bool {
        guard let day else { return from == nil && to == nil }
        if let from, day < from { return false }
        if let to, day > to { return false }
        return true
    }

    public var label: String { label(now: Date()) }

    public func label(now: Date) -> String {
        func text(_ day: String) -> String { FrenchFormat.longDate(fromAPI: day, now: now) }
        switch (from, to) {
        case (nil, nil): return "Toutes les dates"
        case (nil, let to?): return "Jusqu'au \(text(to))"
        case (let from?, nil): return "À partir du \(text(from))"
        case (let from?, let to?) where from == to: return "Le \(text(from))"
        case (let from?, let to?): return "Du \(text(from)) au \(text(to))"
        }
    }
}

/// Dernier e-mail échangé avec un contact (e-mails synchronisés dans Pipedrive).
public struct MailHint: Hashable, Sendable {
    public let subject: String
    public let pipedriveThreadID: Int?
    /// Identifiant Gmail du message, déduit du chemin de stockage Pipedrive.
    public let gmailMessageID: String?

    public init(subject: String, pipedriveThreadID: Int?, gmailMessageID: String?) {
        self.subject = subject
        self.pipedriveThreadID = pipedriveThreadID
        self.gmailMessageID = gmailMessageID
    }

    /// Pipedrive stocke le corps sous « …/<id Gmail>/body » : on en extrait l'identifiant (16 caractères hexadécimaux).
    public static func gmailID(fromStoragePath path: String?) -> String? {
        guard let path else { return nil }
        let withoutQuery = path.split(separator: "?").first.map(String.init) ?? path
        let parts = withoutQuery.split(separator: "/").map(String.init)
        guard let bodyIndex = parts.lastIndex(of: "body"), bodyIndex > 0 else { return nil }
        let candidate = parts[bodyIndex - 1]
        guard (10...24).contains(candidate.count), candidate.allSatisfy({ $0.isHexDigit }) else { return nil }
        return candidate.lowercased()
    }

    init?(message json: JSONValue) {
        let data = json["data"].isNull ? json : json["data"]
        guard data["id"].intValue != nil else { return nil }
        self.init(
            subject: data["subject"].stringValue ?? "",
            pipedriveThreadID: data["mail_thread_id"].intValue,
            gmailMessageID: Self.gmailID(fromStoragePath: data["s3_bucket_path"].stringValue)
                ?? Self.gmailID(fromStoragePath: data["body_url"].stringValue)
        )
    }
}
