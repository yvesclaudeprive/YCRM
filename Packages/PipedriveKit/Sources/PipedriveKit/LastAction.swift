import Foundation

/// « Dernière action » d'une carte (demande d'Yves du 18/11/2026) : en un coup d'œil, la dernière fois que j'ai essayé
/// de joindre le contact et comment (répondeur, appel, message vocal, SMS…), sous les boutons d'historique.
/// Les e-mails n'y sont jamais (« ça peut être troublant »), ni les tâches, ni les appels manqués du client.
public struct LastAction: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case call, voicemail, message, meeting
    }

    public let kind: Kind
    /// « Répondeur », « Call effectué », « Appel Aircall (4 min) », « SMS envoyé »…
    public let label: String
    public let date: Date
    /// Faux si seul le jour est connu (activité sans heure).
    public let hasTime: Bool
    public let activityID: Int

    public init(kind: Kind, label: String, date: Date, hasTime: Bool, activityID: Int) {
        self.kind = kind
        self.label = label
        self.date = date
        self.hasTime = hasTime
        self.activityID = activityID
    }

    /// « 12 novembre à 16:49 » (heure de Paris).
    public func dateText(now: Date = Date(), timeZone: TimeZone) -> String {
        if hasTime {
            return FrenchFormat.longDate(fromAPI: ISO8601DateFormatter().string(from: date), now: now, timeZone: timeZone)
        }
        return FrenchFormat.longDate(fromAPI: FrenchFormat.apiDay(from: date, timeZone: timeZone), now: now, timeZone: timeZone)
    }

    /// « aujourd'hui », « hier », « il y a 6 j ».
    public func agoText(now: Date = Date(), timeZone: TimeZone) -> String {
        let days = LeadTags.daysBetween(FrenchFormat.apiDay(from: date, timeZone: timeZone),
                                        FrenchFormat.apiDay(from: now, timeZone: timeZone)) ?? 0
        switch days {
        case ...0: return "aujourd'hui"
        case 1: return "hier"
        default: return "il y a \(days) j"
        }
    }

    /// Ligne complète : « Répondeur · 12 novembre à 16:49 · il y a 6 j ».
    public func summary(now: Date = Date(), timeZone: TimeZone) -> String {
        "\(label) · \(dateText(now: now, timeZone: timeZone)) · \(agoText(now: now, timeZone: timeZone))"
    }

    /// Ce que dit une activité terminée, si c'est une action de contact (appel, répondeur, message, rendez-vous).
    public static func describe(_ activity: Activity, typeName: String) -> (kind: Kind, label: String)? {
        guard activity.done else { return nil }
        let key = activity.type.lowercased()
        let name = Label.normalized(typeName)
        let subject = Label.normalized(activity.subject)
        if key.hasPrefix("aircall") {
            if key.contains("sms") || key.contains("mms") || key.contains("whatsapp") {
                return key.contains("outbound") ? (.message, "SMS envoyé (Aircall)") : nil
            }
            // Appel manqué ou message vocal laissé par le client : ce n'est pas mon action.
            if key.contains("missed") { return nil }
            if key.contains("unanswer") { return (.voicemail, "Appel sans réponse") }
            let seconds = AircallLog.seconds(in: PlainText.from(html: activity.note ?? ""))
            let length = seconds.map { $0 >= 60 ? " (\($0 / 60) min)" : "" } ?? ""
            if key.contains("outbound") {
                // Aircall dit « décroché » quand la messagerie répond : moins d'une minute = répondeur.
                if let seconds, seconds < LeadTagRules.minimumCallSeconds { return (.voicemail, "Répondeur Aircall") }
                return (.call, "Appel Aircall" + length)
            }
            if key.contains("inbound") && key.contains("answered") { return (.call, "Appel reçu" + length) }
            return nil
        }
        if key.hasPrefix("call_effectu") || Label.matches(typeName, DebriefTemplate.typeName) { return (.call, "Call effectué") }
        if key.contains("onoff") || name.contains("on/off") || name.contains("onoff") { return (.voicemail, "Répondeur ON/OFF") }
        if (key.contains("pondeur") || name.contains("repondeur")) && (key.contains("aircall") || name.contains("aircall")) {
            return (.voicemail, "Répondeur Aircall")
        }
        if key.contains("pondeur") || name.contains("repondeur") { return (.voicemail, "Répondeur") }
        if key.contains("vocal") || name.contains("vocal") { return (.voicemail, "Msg vocal") }
        if key.contains("coll") || name.contains("collegue") { return (.message, "Msg laissé aux collègues") }
        if key.contains("linkedin") || name.contains("linkedin") { return (.message, "Msg LinkedIn") }
        if key.contains("whatsapp") || name.contains("whatsapp") || subject.contains("whatsapp") {
            return (.message, "WhatsApp envoyé")
        }
        if key.hasPrefix("sms") || name.contains("sms") { return (.message, "SMS envoyé") }
        if key == "call" { return (.call, "Appel") }
        if key == "meeting" || key == "google_agenda" { return (.meeting, "RDV") }
        return nil
    }

    /// Dernière action de contact parmi les activités terminées de l'affaire et du contact. Seulement les miennes (ou
    /// celles de l'utilisateur à qui l'alerte est attribuée) : activités dont il est propriétaire et, pour les journaux
    /// Aircall (toujours attribués au propriétaire du contact), appels passés ou décrochés par lui.
    public static func latest(in activities: [Activity], typeNames: [String: String], ownerID: Int?, ownerName: String?,
                              now: Date = Date()) -> LastAction? {
        var seen = Set<Int>()
        var best: LastAction?
        for activity in activities where seen.insert(activity.id).inserted {
            if let ownerID, let owner = activity.ownerID, owner != ownerID { continue }
            guard let described = describe(activity, typeName: typeNames[activity.type] ?? activity.type) else { continue }
            if activity.type.lowercased().hasPrefix("aircall"), let ownerName,
               let agent = AircallLog.agent(in: PlainText.from(html: activity.note ?? "")),
               !Self.sameName(agent, ownerName) {
                continue
            }
            guard let when = moment(activity), when.date <= now.addingTimeInterval(5 * 60) else { continue }
            if let current = best, current.date >= when.date { continue }
            best = LastAction(kind: described.kind, label: described.label, date: when.date, hasTime: when.hasTime,
                              activityID: activity.id)
        }
        return best
    }

    /// Moment de l'action : échéance avec heure, sinon création dans Pipedrive (moment réel d'une activité notée sans
    /// heure), sinon le jour seul.
    static func moment(_ activity: Activity) -> (date: Date, hasTime: Bool)? {
        if let instant = activity.dueInstant { return (instant, true) }
        if let created = activity.addTime.flatMap(FrenchFormat.parseInstant) {
            let createdDay = String((activity.addTime ?? "").prefix(10))
            // Activité notée le jour même (ou sans date) : l'heure de création est la bonne.
            if activity.dueDate == nil || activity.dueDate.map({ String($0.prefix(10)) }) == createdDay {
                return (created, true)
            }
        }
        guard let day = activity.dueDate, let date = FrenchFormat.date(fromAPIDay: String(day.prefix(10)),
                                                                        timeZone: TimeZone(identifier: "Europe/Paris") ?? .current)
        else { return nil }
        return (date, false)
    }

    /// « Yves ATTIAS » et « Yves Attias » : même personne (accents, majuscules et ordre ignorés ; un prénom seul suffit).
    static func sameName(_ a: String, _ b: String) -> Bool {
        let left = Set(Label.normalized(a).split(separator: " ").map(String.init))
        let right = Set(Label.normalized(b).split(separator: " ").map(String.init))
        guard !left.isEmpty, !right.isEmpty else { return true }
        return left.isSubset(of: right) || right.isSubset(of: left)
    }
}

extension AircallLog {
    /// Qui a passé ou décroché l'appel : « Made by Yves ATTIAS », « Answered by Corentin LEROY ».
    public static func agent(in text: String) -> String? {
        guard let range = text.range(of: #"(?i)\b(?:made|answered) by\s*:?\s*[^\n]+"#, options: .regularExpression) else {
            return nil
        }
        let line = String(text[range])
        guard let by = line.range(of: #"(?i)\bby\s*:?\s*"#, options: .regularExpression) else { return nil }
        let name = line[by.upperBound...].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}
