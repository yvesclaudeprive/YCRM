import Foundation

/// Famille d'une ligne d'historique (donne sa couleur dans l'app).
public enum HistoryKind: String, Sendable, Hashable {
    case note, call, voicemail, message, mail, meeting, task, other

    public var label: String {
        switch self {
        case .note: return "Note"
        case .call: return "Appel"
        case .voicemail: return "Répondeur"
        case .message: return "Message"
        case .mail: return "Mail"
        case .meeting: return "Rendez-vous"
        case .task: return "Tâche"
        case .other: return "Activité"
        }
    }

    /// Déduit du type d'activité Pipedrive (clé ou nom).
    public init(activityType key: String, name: String) {
        let text = Label.normalized(key + " " + name)
        if text.contains("pondeur") || text.contains("voicemail") || text.contains("vocal") || text.contains("missed") {
            self = .voicemail
        } else if text.contains("sms") || text.contains("msg") || text.contains("whatsapp") || text.contains("linkedin")
                    || text.contains("message") || text.contains("mms") {
            self = .message
        } else if text.contains("call") || text.contains("appel") {
            self = .call
        } else if text.contains("mail") {
            self = .mail
        } else if text.contains("agenda") || text.contains("meeting") || text.contains("rdv") || text.contains("rendez") {
            self = .meeting
        } else if text.contains("task") || text.contains("tache") || text.contains("todo") {
            self = .task
        } else {
            self = .other
        }
    }
}

/// Une ligne de l'historique d'une activité : note Pipedrive ou activité commentée.
public struct HistoryEntry: Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: HistoryKind
    public let date: Date?
    public let dateText: String
    /// « Note » ou nom du type d'activité (« Call effectué »…), suivi du sujet.
    public let title: String
    public let author: String?
    public let text: String
    /// Texte généré automatiquement (journal Aircall : répondeur, appel décroché…) : affichage court sur 2 lignes.
    public let isAutomatic: Bool
    /// Outil d'appel (logo affiché après le titre) : Aircall ou OnOff.
    public let channel: HistoryChannel?
    /// Pastille : nom du type (« Répondeur »), « Répondeur + Msg vocal » quand un message vocal a été laissé.
    public let badge: String
    /// Pastille d'un répondeur où un message vocal a été laissé (icône : combiné barré + bande).
    public static let voiceMessageBadge = "Répondeur + Msg vocal"

    public init(id: String, kind: HistoryKind, date: Date?, dateText: String, title: String, author: String?, text: String,
                isAutomatic: Bool = false, channel: HistoryChannel? = nil, badge: String? = nil) {
        self.id = id
        self.kind = kind
        self.date = date
        self.dateText = dateText
        self.title = title
        self.author = author
        self.text = text
        self.isAutomatic = isAutomatic
        self.channel = channel
        self.badge = badge ?? kind.label
    }

    func with(title: String? = nil, text: String? = nil, channel: HistoryChannel? = nil) -> HistoryEntry {
        HistoryEntry(id: id, kind: kind, date: date, dateText: dateText, title: title ?? self.title, author: author,
                     text: text ?? self.text, isAutomatic: isAutomatic, channel: channel ?? self.channel, badge: badge)
    }
}

/// Outil avec lequel l'appel a été passé (demande d'Yves du 09/11/2026 : logo après « Répondeur Aircall » /
/// « Répondeur ON/OFF »).
public enum HistoryChannel: String, Sendable, Hashable {
    case aircall, onoff

    /// Déduit du type d'activité (« aircall_… », « Répondeur ON/OFF », « Répondeur Aircall »).
    init?(activityType key: String, name: String) {
        let text = Label.normalized(key + " " + name)
        if text.contains("aircall") {
            self = .aircall
        } else if text.contains("onoff") || text.contains("on/off") || text.contains("on off") {
            self = .onoff
        } else {
            return nil
        }
    }
}

/// Journal automatique d'Aircall (appels, répondeurs) : résumé court en français.
public enum AircallLog {
    /// Vrai pour les appels et messages vocaux journalisés par Aircall (pas les SMS, qui ont un vrai contenu).
    public static func isAutomaticCall(type key: String, text: String) -> Bool {
        let lower = key.lowercased()
        guard lower.hasPrefix("aircall") else { return false }
        if lower.contains("sms") || lower.contains("mms") || lower.contains("whatsapp") { return false }
        return true
    }

    /// « Appel sortant décroché », « Appel manqué avec message »…
    public static func frenchTitle(type key: String, fallback: String) -> String {
        let lower = key.lowercased()
        if lower.contains("outbound_answered") { return "Appel sortant décroché" }
        if lower.contains("inbound_answered") { return "Appel entrant décroché" }
        if lower.contains("outbound_unanswer") { return "Appel sortant sans réponse" }
        if lower.contains("missed_call_with_v") { return "Appel manqué, message vocal" }
        if lower.contains("missed_call") { return "Appel manqué" }
        if lower.contains("voicemail") { return "Message vocal" }
        return fallback
    }

    /// Message Aircall (SMS, MMS, WhatsApp) : qui l'envoie, à qui, et le texte.
    public struct Message: Equatable, Sendable {
        public let isOutbound: Bool
        public let from: String?
        public let to: String?
        public let body: String
    }

    public static func isMessage(type key: String) -> Bool {
        let lower = key.lowercased()
        return lower.hasPrefix("aircall") && (lower.contains("sms") || lower.contains("mms") || lower.contains("whatsapp"))
    }

    /// Lit le journal Aircall d'un message. Libellés réels : « SMS send to: », « Send by: », « SMS sent: »
    /// (sortant) ; « SMS send by: », « SMS received: » (entrant) ; « Aircall number: » (ligne). Le reste est ignoré.
    public static func message(type key: String, text: String) -> Message? {
        let isOutbound = key.lowercased().contains("outbound")
        var fields: [String: String] = [:]
        var bodyLines: [String]?
        var readingBody = false
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if readingBody {
                // Le texte du SMS peut tenir sur plusieurs lignes, jusqu'à la ligne vide suivante.
                if line.isEmpty { readingBody = false } else { bodyLines?.append(line) }
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let label = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if label.hasSuffix(" to") || label == "to" {
                if !value.isEmpty { fields["to"] = value }
            } else if label.hasSuffix(" by") || label == "from" {
                if !value.isEmpty { fields["from"] = value }
            } else if label.hasPrefix("aircall number") || label == "line" {
                if !value.isEmpty { fields["line"] = value }
            } else if bodyLines == nil, label == "sms sent" || label.hasSuffix("received") || label.hasSuffix("body")
                        || label.hasSuffix("message") || label.hasSuffix("content") || label.hasSuffix("text") {
                bodyLines = value.isEmpty ? [] : [value]
                readingBody = true
            }
        }
        guard let lines = bodyLines, !lines.isEmpty else { return nil }
        let body = lines.joined(separator: "\n")
        // Ligne Aircall « Nom (+33…) » → « Nom ».
        let line = fields["line"].map { value -> String in
            guard let parenthesis = value.firstIndex(of: "(") else { return value }
            return value[..<parenthesis].trimmingCharacters(in: .whitespaces)
        }
        if isOutbound {
            return Message(isOutbound: true, from: fields["from"] ?? line, to: fields["to"], body: body)
        }
        return Message(isOutbound: false, from: fields["from"], to: line ?? fields["to"], body: body)
    }

    /// Numéro du journal → nom du contact s'il correspond à l'un de ses numéros.
    static func displayName(_ value: String?, contact: PersonContact?) -> String? {
        guard let value else { return nil }
        guard let contact, let number = PhoneNumber.e164(value),
              contact.phones.contains(where: { PhoneNumber.e164($0.value) == number }) else { return value }
        return contact.name
    }

    /// Durée de conversation lue dans le journal (« Duration of call: 00:02:15 »), en secondes. L'attente avant que
    /// ça décroche (« Waiting time: 00:00:11 », écrite avant la durée dans les appels entrants) n'est pas une durée.
    public static func seconds(in text: String) -> Int? {
        var rest = text
        while let waiting = rest.range(of: #"(?i)waiting time\W{0,5}\d{2}:\d{2}:\d{2}"#, options: .regularExpression) {
            rest.removeSubrange(waiting)
        }
        return clock(in: rest)
    }

    /// Sonnerie (« Waiting time: 00:00:08 ») d'un appel sans réponse ou manqué, en secondes.
    public static func waitingSeconds(in text: String) -> Int? {
        guard let range = text.range(of: #"(?i)waiting time\W{0,5}\d{2}:\d{2}:\d{2}"#, options: .regularExpression) else {
            return nil
        }
        return clock(in: String(text[range]))
    }

    static func clock(in text: String) -> Int? {
        guard let range = text.range(of: "\\b\\d{2}:\\d{2}:\\d{2}\\b", options: .regularExpression) else { return nil }
        let parts = text[range].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    /// Durée lue dans le journal (« 00:02:15 ») → « 2 min 15 s ».
    public static func duration(in text: String) -> String? {
        Self.seconds(in: text).map(Self.spoken)
    }

    /// « 2 min 15 s », « 14 s », « 1 h 05 ».
    static func spoken(_ total: Int) -> String {
        let (hours, minutes, seconds) = (total / 3600, total % 3600 / 60, total % 60)
        if hours > 0 { return "\(hours) h \(String(format: "%02ld", minutes))" }
        if minutes > 0 { return seconds > 0 ? "\(minutes) min \(seconds) s" : "\(minutes) min" }
        return "\(seconds) s"
    }

    /// Appel sans réponse ou manqué : on n'a pas eu le contact.
    public static func isUnanswered(type key: String) -> Bool {
        let lower = key.lowercased()
        return lower.contains("unanswer") || lower.contains("missed")
    }

    /// Deuxième ligne de la carte courte : « Durée 2 min 15 s » (décroché) ou « Sonnerie 8 s » (sans réponse, manqué).
    public static func summary(type key: String, text: String) -> String {
        if isUnanswered(type: key) {
            return waitingSeconds(in: text).map { "Sonnerie \(spoken($0))" } ?? ""
        }
        return duration(in: text).map { "Durée \($0)" } ?? ""
    }
}

/// Note Pipedrive brute (v1 `/notes`).
public struct PipedriveNote: Hashable, Sendable, Identifiable {
    public let id: Int
    public let html: String
    public let addTime: String?
    public let userID: Int?
    public let authorName: String?
    /// Affaire de la note (nil : note de la personne ou de la société seulement).
    public let dealID: Int?

    public init(id: Int, html: String, addTime: String?, userID: Int?, authorName: String?, dealID: Int? = nil) {
        self.id = id
        self.html = html
        self.addTime = addTime
        self.userID = userID
        self.authorName = authorName
        self.dealID = dealID
    }

    init?(json: JSONValue) {
        guard let id = json["id"].intValue else { return nil }
        self.init(id: id, html: json["content"].stringValue ?? "", addTime: json["add_time"].stringValue,
                  userID: json["user_id"].intValue, authorName: json["user"]["name"].stringValue,
                  dealID: json["deal_id"].intValue)
    }

    public var date: Date? { addTime.flatMap(FrenchFormat.parseInstant) }

    public func dateText(now: Date = Date(), weekday: Bool = false) -> String {
        addTime.map { FrenchFormat.longDate(fromAPI: $0, now: now, weekday: weekday) } ?? ""
    }

    /// Note créée par Leexi (compte rendu d'appel) : elle commence par un lien vers l'appel dans Leexi.
    public var isLeexi: Bool {
        html.range(of: "leexi.ai/", options: .caseInsensitive) != nil || html.contains("Utilisateurs Leexi")
    }
}

/// Appel Leexi (compte rendu enregistré dans une note Pipedrive).
public struct LeexiCall: Hashable, Sendable, Identifiable {
    public let id: String
    public let date: Date?
    public let dateText: String
    public let title: String
    public let link: URL?
    public let summary: String

    public init(id: String, date: Date?, dateText: String, title: String, link: URL?, summary: String) {
        self.id = id
        self.date = date
        self.dateText = dateText
        self.title = title
        self.link = link
        self.summary = summary
    }

    /// Lecture d'une note Leexi : lien et titre de l'appel (1er lien), puis le résumé.
    public init(note: PipedriveNote, now: Date = Date()) {
        let html = note.html
        var title = "Appel Leexi"
        var link: URL?
        if let anchor = html.range(of: "<a[^>]*href=\"([^\"]*leexi\\.ai[^\"]*)\"[^>]*>(.*?)</a>",
                                   options: [.regularExpression, .caseInsensitive]) {
            let tag = String(html[anchor])
            if let hrefStart = tag.range(of: "href=\""),
               let hrefEnd = tag[hrefStart.upperBound...].firstIndex(of: "\"") {
                link = URL(string: PlainText.decodeEntities(String(tag[hrefStart.upperBound..<hrefEnd])))
            }
            let text = PlainText.from(html: tag)
            if !text.isEmpty { title = text }
        }
        let summaryHTML: String
        if let marker = html.range(of: "Résumé de l'appel", options: .caseInsensitive)
            ?? html.range(of: "Résumé de l’appel", options: .caseInsensitive) {
            summaryHTML = String(html[marker.upperBound...])
        } else {
            summaryHTML = html
        }
        var summary = PlainText.from(html: summaryHTML)
        while summary.hasPrefix(":") { summary = String(summary.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
        self.init(id: "leexi-\(note.id)", date: note.date, dateText: note.dateText(now: now, weekday: true), title: title, link: link,
                  summary: summary)
    }

    /// L'utilisateur fait partie de l'appel (son adresse figure dans « Utilisateurs Leexi »).
    static func involves(_ note: PipedriveNote, userID: Int?, email: String?) -> Bool {
        if let userID, note.userID == userID { return true }
        guard let email, !email.isEmpty else { return false }
        return note.html.range(of: email, options: .caseInsensitive) != nil
    }
}

/// Historique d'une activité, en deux blocs : notes + activités commentées, et appels Leexi.
public struct HistoryBundle: Hashable, Sendable {
    public let entries: [HistoryEntry]
    public let leexi: [LeexiCall]

    public init(entries: [HistoryEntry], leexi: [LeexiCall]) {
        self.entries = entries
        self.leexi = leexi
    }
}

/// Texte lisible à partir du HTML des notes Pipedrive.
public enum PlainText {
    static let entities: [String: String] = [
        "nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë", "agrave": "à", "acirc": "â",
        "ccedil": "ç", "icirc": "î", "iuml": "ï", "ocirc": "ô", "ugrave": "ù", "ucirc": "û",
        "Eacute": "É", "Egrave": "È", "Agrave": "À", "Ccedil": "Ç",
        "rsquo": "’", "lsquo": "‘", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»",
        "hellip": "…", "euro": "€", "ndash": "–", "mdash": "—", "oelig": "œ",
    ]

    /// Convertit le HTML Pipedrive en texte : retours à la ligne, paragraphes, titres et listes à puces
    /// (imbriquées, avec retrait : « • », « ◦ », « ▪ » ; listes numérotées « 1. »).
    public static func from(html: String) -> String {
        var output = ""
        var lists: [(ordered: Bool, counter: Int)] = []

        func ensureNewline() {
            if !output.isEmpty && !output.hasSuffix("\n") { output += "\n" }
        }

        var index = html.startIndex
        while index < html.endIndex {
            guard html[index] == "<", let close = html[index...].firstIndex(of: ">") else {
                output.append(html[index])
                index = html.index(after: index)
                continue
            }
            let tag = html[html.index(after: index)..<close].lowercased()
            index = html.index(after: close)
            let isClosing = tag.hasPrefix("/")
            let name = String(tag.drop(while: { $0 == "/" }).prefix(while: { $0.isLetter || $0.isNumber }))
            switch name {
            case "br":
                output += "\n"
            case "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "tr":
                ensureNewline()
            case "ul", "ol":
                ensureNewline()
                if isClosing {
                    if !lists.isEmpty { lists.removeLast() }
                } else {
                    lists.append((ordered: name == "ol", counter: 0))
                }
            case "li":
                guard !isClosing else { break }
                ensureNewline()
                let depth = max(lists.count, 1)
                var marker = ["•", "◦", "▪"][min(depth - 1, 2)]
                if !lists.isEmpty && lists[lists.count - 1].ordered {
                    lists[lists.count - 1].counter += 1
                    marker = "\(lists[lists.count - 1].counter)."
                }
                output += String(repeating: "\u{2003}\u{2003}", count: depth - 1) + marker + " "
            default:
                break
            }
        }

        let decoded = decodeEntities(output)
        let lines = decoded.components(separatedBy: "\n").map { line -> String in
            // Espaces normaux réduits ; le retrait des listes (espaces cadratin) est conservé.
            line.replacingOccurrences(of: "[ \t\u{00A0}]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        }
        var result: [String] = []
        for line in lines where !(line.isEmpty && (result.last?.isEmpty ?? true)) {
            result.append(line)
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&", let semicolon = text[index...].firstIndex(of: ";"),
               text.distance(from: index, to: semicolon) <= 10 {
                let name = String(text[text.index(after: index)..<semicolon])
                if let decoded = decode(entity: name) {
                    output += decoded
                    index = text.index(after: semicolon)
                    continue
                }
            }
            output.append(text[index])
            index = text.index(after: index)
        }
        return output
    }

    static func decode(entity name: String) -> String? {
        if let named = entities[name] { return named }
        guard name.hasPrefix("#") else { return nil }
        let digits = name.dropFirst()
        let value: UInt32? = digits.lowercased().hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
        guard let value, let scalar = Unicode.Scalar(value) else { return nil }
        return String(Character(scalar))
    }
}

/// Dernières notes, activités commentées et appels Leexi liés à une activité (affaire, personne, société).
/// Seuls les éléments de l'utilisateur à qui l'activité est attribuée sont gardés (pas les appels des collègues).
/// Périmètre de l'historique d'une affaire (demande d'Yves du 12/11/2026 : « il faut se focus sur l'affaire en
/// question », des éléments de 2019 d'une autre affaire de la même société remontaient) : les notes et activités
/// d'une **autre affaire** sont exclues ; celles rattachées seulement à la personne ou à la société ne comptent qu'à
/// partir de `leadDays` jours avant la création de l'affaire (le 1er appel précède souvent la création de l'affaire).
/// Sans affaire (activité rattachée à une personne ou une société), rien n'est filtré.
public struct HistoryScope: Sendable {
    public static let leadDays = 30
    public let dealID: Int?
    public let since: Date?

    public init(dealID: Int?, dealCreated: Date?) {
        self.dealID = dealID
        self.since = dealID == nil ? nil : dealCreated.map { $0.addingTimeInterval(-Double(Self.leadDays) * 86_400) }
    }

    /// Élément rattaché à `otherDeal` (nil : à la personne ou la société seulement), daté de `date`.
    public func includes(deal otherDeal: Int?, date: Date?) -> Bool {
        guard let dealID else { return true }
        if let otherDeal { return otherDeal == dealID }
        guard let since, let date else { return true }
        return date >= since
    }
}

public struct HistoryLoader: Sendable {
    let client: PipedriveClient

    public init(client: PipedriveClient) {
        self.client = client
    }

    public func load(for item: ActivityItem, typeNames: [String: String], ownerID: Int?, ownerEmail: String?,
                     limit: Int = 100, now: Date = Date()) async throws -> HistoryBundle {
        let dealID = item.activity.dealID
        let personID = item.person?.id ?? item.activity.personID
        let orgID = item.orgID
        let scope = HistoryScope(dealID: dealID, dealCreated: item.deal?.id == dealID ? item.deal?.createdAt : nil)

        let activityFilter: (String, Int)? = dealID.map { ("deal_id", $0) }
            ?? personID.map { ("person_id", $0) } ?? orgID.map { ("org_id", $0) }
        async let dealNotes = notes("deal_id", dealID)
        async let personNotes = notes("person_id", personID)
        async let orgNotes = notes("org_id", orgID)
        async let related = activities(activityFilter)
        // Appels et messages du contact rattachés à lui seul (tentatives pour l'avoir), filtrés par `HistoryScope`.
        async let personRelated = personActivities(personID, besides: dealID)

        var seenNotes = Set<Int>()
        var entries: [HistoryEntry] = []
        var calls: [LeexiCall] = []
        let allNotes = try await dealNotes + personNotes + orgNotes
        for note in allNotes where seenNotes.insert(note.id).inserted {
            guard scope.includes(deal: note.dealID, date: note.date) else { continue }
            if note.isLeexi {
                if LeexiCall.involves(note, userID: ownerID, email: ownerEmail) { calls.append(LeexiCall(note: note, now: now)) }
                continue
            }
            if let ownerID, let author = note.userID, author != ownerID { continue }
            let text = PlainText.from(html: note.html)
            guard !text.isEmpty else { continue }
            entries.append(HistoryEntry(id: "note-\(note.id)", kind: .note, date: note.date, dateText: note.dateText(now: now, weekday: true),
                                        title: "Note", author: note.authorName, text: text))
        }
        let dealActivities = try await related
        var seenActivities = Set(dealActivities.map(\.id))
        let personList = await personRelated
        // Seulement les appels et messages du contact sans affaire, depuis le début de cette affaire (`HistoryScope`).
        let extraActivities = personList.filter { activity in
            guard seenActivities.insert(activity.id).inserted else { return false }
            return activity.dealID == nil
                && scope.includes(deal: nil, date: activity.dueInstant ?? activity.addTime.flatMap(FrenchFormat.parseInstant))
        }
        let mine = (dealActivities + extraActivities).filter { activity in
            guard let ownerID, let activityOwner = activity.ownerID else { return true }
            return activityOwner == ownerID
        }
        entries += Self.activityEntries(mine, typeNames: typeNames, contact: item.person, now: now)
        let byDate: (Date?, Date?) -> Bool = { ($0 ?? .distantPast) > ($1 ?? .distantPast) }
        return HistoryBundle(
            entries: Array(entries.sorted { byDate($0.date, $1.date) }.prefix(limit)),
            leexi: Array(calls.sorted { byDate($0.date, $1.date) }.prefix(limit))
        )
    }

    private func notes(_ filter: String, _ id: Int?) async throws -> [PipedriveNote] {
        guard let id else { return [] }
        // Historique indicatif : une liste de notes illisible ne bloque pas le reste.
        return (try? await client.notes(filter: filter, id: id)) ?? []
    }

    private func activities(_ filter: (String, Int)?) async throws -> [Activity] {
        guard let filter else { return [] }
        return try await client.activities(filter: filter.0, id: filter.1)
    }

    /// Activités du contact quand l'historique est celui d'une affaire (sinon elles y sont déjà). Indicatif : une
    /// erreur ne bloque pas le reste.
    private func personActivities(_ personID: Int?, besides dealID: Int?) async -> [Activity] {
        guard let personID, dealID != nil else { return [] }
        return (try? await client.activities(filter: "person_id", id: personID)) ?? []
    }

    /// Cartes des activités, sans doublons (demande d'Yves du 09/11/2026) :
    /// - journal Aircall « décroché » juste avant un « Call effectué » (45 min avant à 5 min après) : c'est le même
    ///   appel, une seule carte « Call effectué · 5 min 4 s » avec le logo Aircall (le plus long des journaux) ;
    /// - journal Aircall « décroché » de moins d'une minute = la messagerie a répondu : « Répondeur Aircall », fondu
    ///   dans le « Répondeur… » / « Msg vocal » noté juste après (20 min avant à 5 min après) s'il y en a un ;
    /// - cartes courtes identiques à moins de 15 min d'écart : une seule, « Répondeur Aircall ×2 ».
    static func activityEntries(_ activities: [Activity], typeNames: [String: String], contact: PersonContact?,
                                now: Date) -> [HistoryEntry] {
        func typeName(_ activity: Activity) -> String { typeNames[activity.type] ?? activity.type }
        func kind(_ activity: Activity) -> HistoryKind { HistoryKind(activityType: activity.type, name: typeName(activity)) }
        func moment(_ activity: Activity) -> Date? {
            activity.dueInstant ?? activity.addTime.flatMap(FrenchFormat.parseInstant)
        }
        func isAircall(_ activity: Activity) -> Bool { activity.type.lowercased().hasPrefix("aircall") }
        func isAnsweredLog(_ activity: Activity) -> Bool {
            let lower = activity.type.lowercased()
            return isAircall(activity) && lower.contains("answered") && !AircallLog.isUnanswered(type: lower)
                && AircallLog.isAutomaticCall(type: lower, text: "")
        }
        func seconds(_ activity: Activity) -> Int? { AircallLog.seconds(in: PlainText.from(html: activity.note ?? "")) }
        func isShort(_ activity: Activity) -> Bool { (seconds(activity) ?? 0) < LeadTagRules.minimumCallSeconds }

        let logs = activities.filter(isAnsweredLog)
        var usedLogs = Set<Int>()
        var mergedCall: [Int: Int?] = [:]          // « Call effectué » → durée de l'appel Aircall fondu
        var aircallVoicemail = Set<Int>()            // « Répondeur… » noté après un répondeur Aircall
        var manual: [(activity: Activity, time: Date)] = []
        for activity in activities where !isAircall(activity) && activity.done {
            if let time = moment(activity) { manual.append((activity, time)) }
        }
        manual.sort { (a: (activity: Activity, time: Date), b: (activity: Activity, time: Date)) -> Bool in a.time < b.time }
        for (activity, time) in manual {
            let window: (before: TimeInterval, after: TimeInterval)
            switch kind(activity) {
            case .call: window = (45 * 60, 5 * 60)
            case .voicemail: window = (20 * 60, 5 * 60)
            default: continue
            }
            let earliest = time.addingTimeInterval(-window.before)
            let latest = time.addingTimeInterval(window.after)
            var candidates: [Activity] = []
            for log in logs where !usedLogs.contains(log.id) {
                if let start = moment(log), start >= earliest, start <= latest { candidates.append(log) }
            }
            if kind(activity) == .call {
                guard let longest = candidates.max(by: { (seconds($0) ?? 0) < (seconds($1) ?? 0) }) else { continue }
                usedLogs.insert(longest.id)
                mergedCall[activity.id] = seconds(longest)
            } else {
                let short = candidates.filter(isShort)
                guard !short.isEmpty else { continue }
                short.forEach { usedLogs.insert($0.id) }
                aircallVoicemail.insert(activity.id)
            }
        }

        var entries: [HistoryEntry] = []
        for activity in activities where !usedLogs.contains(activity.id) {
            let text = PlainText.from(html: activity.note ?? "")
            let name = typeName(activity)
            let date = activity.dueInstant ?? activity.dueDate.flatMap { FrenchFormat.parseInstant("\($0)T12:00:00Z") }
            let dateText = activity.displayDate(now: now, weekday: true)
            let activityKind = kind(activity)
            let id = "activity-\(activity.id)"
            var channel = HistoryChannel(activityType: activity.type, name: name)
            if aircallVoicemail.contains(activity.id), channel == nil { channel = .aircall }
            let normalizedName = Label.normalized(name + " " + activity.subject)
            let leftMessage = normalizedName.contains("msg vocal") || normalizedName.contains("message vocal")
            let badge: String? = activityKind == .voicemail && !isAircall(activity) && leftMessage ? HistoryEntry.voiceMessageBadge : nil
            if let merged = mergedCall[activity.id] {
                // « Call effectué » + son appel Aircall : une seule carte.
                let spoken = merged.map(AircallLog.spoken)
                let title = Self.title(activity, typeName: name)
                if text.isEmpty {
                    entries.append(HistoryEntry(id: id, kind: activityKind, date: date, dateText: dateText, title: title,
                                                author: nil, text: spoken.map { "Durée \($0)" } ?? "", isAutomatic: true,
                                                channel: .aircall, badge: badge))
                } else {
                    entries.append(HistoryEntry(id: id, kind: activityKind, date: date, dateText: dateText,
                                                title: spoken.map { "\(title) · \($0)" } ?? title, author: nil, text: text,
                                                channel: .aircall, badge: badge))
                }
                continue
            }
            if text.isEmpty {
                // Tentative sans commentaire (« Msg vocal », « Répondeur ON/OFF », « Sms envoyé »…, demande d'Yves du
                // 09/11/2026 : voir qu'on a essayé de l'avoir) : carte courte, seulement si elle a été faite.
                guard activity.done, [.call, .voicemail, .message].contains(activityKind) else { continue }
                entries.append(HistoryEntry(id: id, kind: activityKind, date: date, dateText: dateText,
                                            title: Self.title(activity, typeName: name), author: nil, text: "",
                                            isAutomatic: true, channel: channel, badge: badge))
                continue
            }
            if AircallLog.isMessage(type: activity.type), let message = AircallLog.message(type: activity.type, text: text) {
                // SMS / WhatsApp Aircall : seulement qui écrit à qui, et le message.
                let medium = activity.type.lowercased().contains("whatsapp") ? "WhatsApp" : "SMS"
                let direction = message.isOutbound ? "\(medium) envoyé" : "\(medium) reçu"
                let route = [AircallLog.displayName(message.from, contact: contact),
                             AircallLog.displayName(message.to, contact: contact)]
                    .compactMap { $0 }.joined(separator: " → ")
                entries.append(HistoryEntry(id: id, kind: .message, date: date, dateText: dateText,
                                            title: route.isEmpty ? direction : "\(direction) · \(route)", author: nil,
                                            text: message.body, channel: .aircall))
                continue
            }
            if AircallLog.isAutomaticCall(type: activity.type, text: text) {
                // Journal Aircall : titre en français + durée (ou sonnerie), sur 2 lignes. Décroché moins d'une minute
                // = la messagerie a répondu : « Répondeur Aircall ».
                if isAnsweredLog(activity), isShort(activity) {
                    entries.append(HistoryEntry(id: id, kind: .voicemail, date: date, dateText: dateText,
                                                title: "Répondeur Aircall", author: nil,
                                                text: AircallLog.summary(type: activity.type, text: text), isAutomatic: true,
                                                channel: .aircall))
                } else {
                    entries.append(HistoryEntry(id: id, kind: activityKind, date: date, dateText: dateText,
                                                title: AircallLog.frenchTitle(type: activity.type, fallback: name), author: nil,
                                                text: AircallLog.summary(type: activity.type, text: text), isAutomatic: true,
                                                channel: .aircall))
                }
                continue
            }
            entries.append(HistoryEntry(id: id, kind: activityKind, date: date, dateText: dateText,
                                        title: Self.title(activity, typeName: name), author: nil, text: text,
                                        channel: channel, badge: badge))
        }
        return collapseRepeats(entries)
    }

    /// Cartes courtes identiques (même titre, même outil) à moins de 15 min d'écart : une seule, « ×2 ».
    static func collapseRepeats(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        let sorted = entries.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        var result: [HistoryEntry] = []
        var counts: [Int] = []
        for entry in sorted {
            if let last = result.last, last.isAutomatic, entry.isAutomatic, last.title == entry.title,
               last.channel == entry.channel, last.kind == entry.kind,
               let a = last.date, let b = entry.date, abs(a.timeIntervalSince(b)) <= 15 * 60 {
                counts[counts.count - 1] += 1
                continue
            }
            result.append(entry)
            counts.append(1)
        }
        return zip(result, counts).map { entry, count in
            count > 1 ? entry.with(title: "\(entry.title) ×\(count)", text: "") : entry
        }
    }

    /// « Call effectué », « Sms envoyé · WhatsApp envoyé » : le type, puis le texte s'il dit autre chose.
    static func title(_ activity: Activity, typeName: String) -> String {
        activity.subject.isEmpty || Label.matches(activity.subject, typeName) ? typeName : "\(typeName) · \(activity.subject)"
    }
}
