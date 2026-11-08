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

    public init(id: String, kind: HistoryKind, date: Date?, dateText: String, title: String, author: String?, text: String,
                isAutomatic: Bool = false) {
        self.id = id
        self.kind = kind
        self.date = date
        self.dateText = dateText
        self.title = title
        self.author = author
        self.text = text
        self.isAutomatic = isAutomatic
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

    /// Durée lue dans le journal (« 00:02:15 »), en secondes.
    public static func seconds(in text: String) -> Int? {
        guard let range = text.range(of: "\\b\\d{2}:\\d{2}:\\d{2}\\b", options: .regularExpression) else { return nil }
        let parts = text[range].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    /// Durée lue dans le journal (« 00:02:15 ») → « 2 min 15 s ».
    public static func duration(in text: String) -> String? {
        guard let total = Self.seconds(in: text) else { return nil }
        let (hours, minutes, seconds) = (total / 3600, total % 3600 / 60, total % 60)
        if hours > 0 { return "\(hours) h \(String(format: "%02ld", minutes))" }
        if minutes > 0 { return seconds > 0 ? "\(minutes) min \(seconds) s" : "\(minutes) min" }
        return "\(seconds) s"
    }
}

/// Note Pipedrive brute (v1 `/notes`).
public struct PipedriveNote: Hashable, Sendable, Identifiable {
    public let id: Int
    public let html: String
    public let addTime: String?
    public let userID: Int?
    public let authorName: String?

    public init(id: Int, html: String, addTime: String?, userID: Int?, authorName: String?) {
        self.id = id
        self.html = html
        self.addTime = addTime
        self.userID = userID
        self.authorName = authorName
    }

    init?(json: JSONValue) {
        guard let id = json["id"].intValue else { return nil }
        self.init(id: id, html: json["content"].stringValue ?? "", addTime: json["add_time"].stringValue,
                  userID: json["user_id"].intValue, authorName: json["user"]["name"].stringValue)
    }

    public var date: Date? { addTime.flatMap(FrenchFormat.parseInstant) }

    public func dateText(now: Date = Date()) -> String {
        addTime.map { FrenchFormat.longDate(fromAPI: $0, now: now) } ?? ""
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
        self.init(id: "leexi-\(note.id)", date: note.date, dateText: note.dateText(now: now), title: title, link: link,
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

        let activityFilter: (String, Int)? = dealID.map { ("deal_id", $0) }
            ?? personID.map { ("person_id", $0) } ?? orgID.map { ("org_id", $0) }
        async let dealNotes = notes("deal_id", dealID)
        async let personNotes = notes("person_id", personID)
        async let orgNotes = notes("org_id", orgID)
        async let related = activities(activityFilter)

        var seenNotes = Set<Int>()
        var entries: [HistoryEntry] = []
        var calls: [LeexiCall] = []
        let allNotes = try await dealNotes + personNotes + orgNotes
        for note in allNotes where seenNotes.insert(note.id).inserted {
            if note.isLeexi {
                if LeexiCall.involves(note, userID: ownerID, email: ownerEmail) { calls.append(LeexiCall(note: note, now: now)) }
                continue
            }
            if let ownerID, let author = note.userID, author != ownerID { continue }
            let text = PlainText.from(html: note.html)
            guard !text.isEmpty else { continue }
            entries.append(HistoryEntry(id: "note-\(note.id)", kind: .note, date: note.date, dateText: note.dateText(now: now),
                                        title: "Note", author: note.authorName, text: text))
        }
        let relatedActivities = try await related
        for activity in relatedActivities {
            if let ownerID, let activityOwner = activity.ownerID, activityOwner != ownerID { continue }
            let text = PlainText.from(html: activity.note ?? "")
            guard !text.isEmpty else { continue }
            let typeName = typeNames[activity.type] ?? activity.type
            let date = activity.dueInstant ?? activity.dueDate.flatMap { FrenchFormat.parseInstant("\($0)T12:00:00Z") }
            let kind = HistoryKind(activityType: activity.type, name: typeName)
            if AircallLog.isMessage(type: activity.type), let message = AircallLog.message(type: activity.type, text: text) {
                // SMS / WhatsApp Aircall : seulement qui écrit à qui, et le message.
                let channel = activity.type.lowercased().contains("whatsapp") ? "WhatsApp" : "SMS"
                let direction = message.isOutbound ? "\(channel) envoyé" : "\(channel) reçu"
                let route = [AircallLog.displayName(message.from, contact: item.person),
                             AircallLog.displayName(message.to, contact: item.person)]
                    .compactMap { $0 }.joined(separator: " → ")
                entries.append(HistoryEntry(
                    id: "activity-\(activity.id)", kind: .message, date: date, dateText: activity.displayDate(now: now),
                    title: route.isEmpty ? direction : "\(direction) · \(route)", author: nil, text: message.body))
                continue
            }
            if AircallLog.isAutomaticCall(type: activity.type, text: text) {
                // Journal Aircall sans commentaire : titre en français + durée, sur 2 lignes.
                entries.append(HistoryEntry(
                    id: "activity-\(activity.id)", kind: kind, date: date, dateText: activity.displayDate(now: now),
                    title: AircallLog.frenchTitle(type: activity.type, fallback: typeName), author: nil,
                    text: AircallLog.duration(in: text).map { "Durée \($0)" } ?? "", isAutomatic: true))
                continue
            }
            let title = activity.subject.isEmpty || Label.matches(activity.subject, typeName)
                ? typeName : "\(typeName) · \(activity.subject)"
            entries.append(HistoryEntry(
                id: "activity-\(activity.id)",
                kind: kind,
                date: date,
                dateText: activity.displayDate(now: now),
                title: title,
                author: nil,
                text: text
            ))
        }
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
}
