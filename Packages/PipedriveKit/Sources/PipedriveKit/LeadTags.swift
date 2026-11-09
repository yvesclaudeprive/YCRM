import Foundation

/// Étiquettes affichées sur une fiche (demande d'Yves du 08/11/2026) :
/// - « Devis envoyé » : une activité terminée « Devis envoyé » (ou dont le texte dit qu'un devis a été envoyé), ou un
///   e-mail de l'agence au client avec un devis en pièce jointe, de moins de 6 mois, sur une affaire en cours et pas
///   encore signée ;
/// - « 1er call à faire » : aucun échange de vive voix connu avec le contact (appel décroché, « Call effectué »,
///   rendez-vous, enregistrement Leexi). Répondeurs, appels manqués, SMS et e-mails ne comptent pas.
public struct LeadTags: Hashable, Sendable {
    /// Devis envoyés sur l'affaire depuis moins de 6 mois (activités terminées et e-mails), le plus récent d'abord :
    /// détail au toucher de l'étiquette.
    public let quotes: [QuoteSent]
    public let firstCallToDo: Bool
    /// Preuve de signature la plus récente (affaire gagnée, champ « Contrat signé le », note ou activité « … signé »).
    public let signature: SignatureEvidence?
    /// Devis envoyés en signature (DocuSign, bon de commande) et pas encore signés, d'après l'analyse de Claude.
    public let signing: [QuoteSent]
    /// Analyse de Claude (champ d'affaire « Devis en attente ») : quand elle existe, elle fait foi.
    public let analysis: QuoteAnalysis?
    /// Accès demandés au client et pas encore reçus, d'après l'analyse de Claude (étiquette « Accès »).
    public let access: [QuoteSent]
    /// Devis que le client attend et qui ne sont pas encore partis, d'après l'analyse de Claude (« Devis à faire »).
    public let toDo: [QuoteSent]
    /// Rendez-vous à venir avec le contact (Google Agenda via l'analyse de Claude, ou activité Pipedrive de type
    /// rendez-vous), le plus proche d'abord ; les rendez-vous passés n'y sont jamais.
    public let meetings: [UpcomingMeeting]

    public init(quotes: [QuoteSent], firstCallToDo: Bool, signature: SignatureEvidence? = nil, signing: [QuoteSent] = [],
                analysis: QuoteAnalysis? = nil, access: [QuoteSent] = [], toDo: [QuoteSent] = [],
                meetings: [UpcomingMeeting] = []) {
        self.quotes = quotes
        self.firstCallToDo = firstCallToDo
        self.signature = signature
        self.signing = signing
        self.analysis = analysis
        self.access = access
        self.toDo = toDo
        self.meetings = meetings
    }

    /// Étiquettes tirées de l'analyse de Claude : « En signature » et « Devis envoyé » devis par devis.
    public init(analysis: QuoteAnalysis, firstCallToDo: Bool, now: Date = Date(), timeZone: TimeZone) {
        self.init(quotes: analysis.quotes(.sent, now: now, timeZone: timeZone), firstCallToDo: firstCallToDo,
                  signing: analysis.quotes(.signing, now: now, timeZone: timeZone), analysis: analysis,
                  access: analysis.quotes(.access, now: now, timeZone: timeZone),
                  toDo: analysis.quotes(.toDo, now: now, timeZone: timeZone),
                  meetings: UpcomingMeeting.upcoming(analysis.entries(.meeting).compactMap {
                      UpcomingMeeting(entry: $0, timeZone: timeZone)
                  }, now: now, timeZone: timeZone))
    }

    /// Les mêmes étiquettes avec d'autres accès en attente et rendez-vous à venir (activités Pipedrive de la liste,
    /// analyse de Claude sans partie devis), sans doublon.
    public func adding(access moreAccess: [QuoteSent] = [], meetings more: [UpcomingMeeting], now: Date = Date(),
                       timeZone: TimeZone) -> LeadTags {
        guard !more.isEmpty || !moreAccess.isEmpty else { return self }
        return LeadTags(quotes: quotes, firstCallToDo: firstCallToDo, signature: signature, signing: signing,
                        analysis: analysis, access: access + moreAccess, toDo: toDo,
                        meetings: UpcomingMeeting.upcoming(meetings + more, now: now, timeZone: timeZone))
    }

    /// Signé : une preuve de signature datée du dernier devis envoyé ou après (un devis plus récent repasse en « envoyé »).
    /// Avec l'analyse de Claude : plus rien en attente et au moins un devis signé.
    public var isSigned: Bool {
        if let analysis { return quotes.isEmpty && signing.isEmpty && toDo.isEmpty && !analysis.entries(.signed).isEmpty }
        guard let signature else { return false }
        guard let quoteDay = quoteSentDay else { return true }
        return signature.day >= quoteDay
    }

    /// Raccourci (tests) : un seul devis envoyé ce jour-là.
    public init(quoteSentDay: String?, firstCallToDo: Bool) {
        self.init(quotes: quoteSentDay.map { [QuoteSent(id: 0, subject: "Devis envoyé", day: $0, dateText: $0, note: nil)] } ?? [],
                  firstCallToDo: firstCallToDo)
    }

    public static let none = LeadTags(quotes: [], firstCallToDo: false)

    /// Un devis de plus de 6 mois n'est plus « en attente » : signé (souvent noté seulement dans l'yntranet) ou abandonné
    /// (retour d'Yves du 08/11/2026).
    public static let pendingWindowDays = 180

    /// Jour (AAAA-MM-JJ, heure de Paris) du dernier « Devis envoyé », s'il y en a un.
    public var quoteSentDay: String? { quotes.first?.day }

    /// Devis envoyé et pas encore signé : seul cas où l'étiquette « Devis envoyé » s'affiche.
    public var hasPendingQuote: Bool { analysis != nil ? !quotes.isEmpty : !quotes.isEmpty && !isSigned }

    /// Devis en signature (DocuSign envoyé, pas encore signé) : étiquette « En signature », plus chaude.
    public var hasSigning: Bool { !signing.isEmpty }

    /// Accès demandés au client et pas encore reçus : étiquette bleue « Accès ».
    public var hasAccessPending: Bool { !access.isEmpty }

    /// Devis attendu par le client et pas encore envoyé : étiquette violette « Devis à faire ».
    public var hasQuoteToDo: Bool { !toDo.isEmpty }

    /// Rendez-vous à venir avec le contact : étiquette verte « RDV à venir ».
    public var hasUpcomingMeeting: Bool { !meetings.isEmpty }

    public var isEmpty: Bool {
        !hasPendingQuote && !hasSigning && !hasQuoteToDo && !hasAccessPending && !firstCallToDo && !hasUpcomingMeeting
    }

    /// Étiquette « RDV à venir - jeu. 12 novembre à 14:00 - dans 3j » : le prochain rendez-vous seulement (il peut
    /// être passé entre-temps : rien alors).
    public func meetingLine(now: Date = Date(), timeZone: TimeZone) -> TagLine? {
        guard let next = UpcomingMeeting.upcoming(meetings, now: now, timeZone: timeZone).first else { return nil }
        return TagLine(prefix: "RDV à venir", title: next.dateText(now: now, timeZone: timeZone),
                       age: next.countdown(now: now, timeZone: timeZone))
    }

    /// Lignes de l'étiquette « Devis à faire » : « Devis à faire - Audit SEO - 11j » (depuis la demande du client).
    public func toDoLines(now: Date = Date(), timeZone: TimeZone) -> [TagLine] {
        Self.lines(prefix: "Devis à faire", toDo, now: now, timeZone: timeZone)
    }

    /// Lignes de l'étiquette « Accès » : « Accès - FTP + back-office - 122j ».
    public func accessLines(now: Date = Date(), timeZone: TimeZone) -> [TagLine] {
        Self.lines(prefix: "Accès", access, now: now, timeZone: timeZone)
    }

    /// Une ligne de l'étiquette (demandes d'Yves du 08/11/2026) : « Devis - SEO / GEO - 149j », le titre en gras dans
    /// l'app, une ligne par devis.
    public struct TagLine: Hashable, Sendable {
        /// « Devis » ou « En signature ».
        public let prefix: String
        public let title: String
        /// « 149j », « auj. » (nil si la date est inconnue).
        public let age: String?

        public var text: String { ([prefix, title] + (age.map { [$0] } ?? [])).joined(separator: " - ") }
    }

    /// Lignes de l'étiquette « En signature » : « En signature - TMA - 2j ».
    public func signingLines(now: Date = Date(), timeZone: TimeZone) -> [TagLine] {
        Self.lines(prefix: "En signature", signing, now: now, timeZone: timeZone)
    }

    /// Lignes de l'étiquette « Devis envoyé » : « Devis - Refonte du site - 206j » (rien si signé).
    public func quoteLines(now: Date = Date(), timeZone: TimeZone) -> [TagLine] {
        guard hasPendingQuote else { return [] }
        return Self.lines(prefix: "Devis", quotes, now: now, timeZone: timeZone)
    }

    static func lines(prefix: String, _ quotes: [QuoteSent], now: Date, timeZone: TimeZone) -> [TagLine] {
        quotes.map { TagLine(prefix: prefix, title: shortTitle($0.subject), age: $0.shortAgoText(now: now, timeZone: timeZone)) }
    }

    /// Noms courts dans les étiquettes, pour gagner de la place (demande d'Yves du 08/11/2026) :
    /// « Google Analytics (4) » → « GA4 », « (Google) Search Console » → « GSC », « montée de version » → « MEV ».
    /// La fenêtre de détail garde les noms longs.
    public static func shortTitle(_ title: String) -> String {
        var text = title
        for (pattern, short) in shortNames {
            text = text.replacingOccurrences(of: pattern, with: short, options: [.regularExpression, .caseInsensitive])
        }
        return text
    }

    static let shortNames: [(String, String)] = [
        (#"\bgoogle[\s-]+analytics(\s*4)?\b"#, "GA4"),
        (#"\bga\s+4\b"#, "GA4"),
        (#"\b(google[\s-]+)?se(ar|ra)ch[\s-]+console\b"#, "GSC"),
        (#"\bmont(é|e)es?\s+(de\s+)?versions?\b"#, "MEV"),
    ]

    /// Texte de l'étiquette « En signature » (une ligne par devis).
    public func signingLabel(now: Date = Date(), timeZone: TimeZone) -> String? {
        let lines = signingLines(now: now, timeZone: timeZone)
        return lines.isEmpty ? nil : lines.map(\.text).joined(separator: "\n")
    }

    /// Texte de l'étiquette « Devis envoyé » : « Devis - Refonte du site - 206j », une ligne par devis ; rien si le
    /// devis est signé (demandes d'Yves du 08/11/2026).
    public func quoteSentLabel(now: Date = Date(), timeZone: TimeZone) -> String? {
        let lines = quoteLines(now: now, timeZone: timeZone)
        return lines.isEmpty ? nil : lines.map(\.text).joined(separator: "\n")
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

/// Un devis envoyé (activité terminée ou e-mail de l'affaire), pour la fenêtre de détail.
public struct QuoteSent: Hashable, Sendable, Identifiable {
    public enum Source: String, Hashable, Sendable {
        /// Activité terminée « Devis envoyé ».
        case activity
        /// E-mail de l'agence au client avec le devis en pièce jointe.
        case mail
        /// Ligne de l'analyse de Claude (champ « Devis en attente »).
        case analysis
    }

    /// Identifiant de l'activité ou de l'e-mail.
    public let id: Int
    public let source: Source
    /// Texte de l'activité (« Devis SEO envoyé ») ou objet de l'e-mail.
    public let subject: String
    /// Jour à l'heure de Paris (AAAA-MM-JJ).
    public let day: String
    /// Date affichée (« 3 novembre à 14:30 »).
    public let dateText: String
    /// Note de l'activité en texte simple, ou pièce jointe de l'e-mail.
    public let note: String?

    public init(id: Int, source: Source = .activity, subject: String, day: String, dateText: String, note: String?) {
        self.id = id
        self.source = source
        self.subject = subject
        self.day = day
        self.dateText = dateText
        self.note = note
    }

    /// « aujourd'hui », « hier », « il y a 5 j ».
    public func agoText(now: Date = Date(), timeZone: TimeZone) -> String? {
        Self.ago(from: day, to: FrenchFormat.apiDay(from: now, timeZone: timeZone))
    }

    /// Format court des étiquettes : « auj. », « 1j », « 149j ».
    public func shortAgoText(now: Date = Date(), timeZone: TimeZone) -> String? {
        guard let days = LeadTags.daysBetween(day, FrenchFormat.apiDay(from: now, timeZone: timeZone)) else { return nil }
        return days <= 0 ? "auj." : "\(days)j"
    }

    public static func ago(from day: String, to today: String) -> String? {
        guard let days = LeadTags.daysBetween(day, today) else { return nil }
        switch days {
        case ..<1: return "aujourd'hui"
        case 1: return "hier"
        default: return "il y a \(days) j"
        }
    }
}

/// Preuve qu'un devis est signé, affichée dans la fenêtre de détail.
public struct SignatureEvidence: Hashable, Sendable {
    public enum Source: String, Hashable, Sendable {
        /// Affaire marquée « Gagnée » dans Pipedrive.
        case dealWon
        /// Champ d'affaire « Contrat signé le » (rempli par exemple depuis l'yntranet).
        case signedField
        /// Note de l'affaire (hors Leexi) : « c'est signé pour SEO / SEA / TMA ».
        case note
        /// Activité terminée dont le texte ou la note dit « signé ».
        case activity
        /// E-mail de l'affaire : « À la suite de la signature du bon de commande », « Bon pour accord » du client…
        case mail
    }

    public let source: Source
    /// Jour à l'heure de Paris (AAAA-MM-JJ).
    public let day: String
    /// Date affichée (« 7 septembre »).
    public let dateText: String
    /// Extrait qui prouve la signature (ou libellé de la source).
    public let text: String

    public init(source: Source, day: String, dateText: String, text: String) {
        self.source = source
        self.day = day
        self.dateText = dateText
        self.text = text
    }

    public var sourceLabel: String {
        switch source {
        case .dealWon: return "Affaire gagnée dans Pipedrive"
        case .signedField: return "Champ « Contrat signé le »"
        case .note: return "Note de l'affaire"
        case .activity: return "Activité de l'affaire"
        case .mail: return "E-mail de l'affaire"
        }
    }
}

/// Règles de lecture des activités Pipedrive pour les étiquettes.
public enum LeadTagRules {
    /// Durée minimale d'un appel Aircall décroché pour compter comme un vrai échange (« 1er call » fait).
    public static let minimumCallSeconds = 60

    /// Échange de vive voix : appel Aircall décroché d'au moins une minute, « Call effectué », appel ou rendez-vous
    /// Pipedrive, événement d'agenda.
    public static func isConversation(_ activity: Activity, typeNames: [String: String]) -> Bool {
        guard activity.done else { return false }
        let key = activity.type.lowercased()
        let name = Label.normalized(typeNames[activity.type] ?? activity.type)
        let notReached = ["unanswer", "missed", "voicemail", "repondeur", "rpondeur", "sms", "msg"]
        if notReached.contains(where: { key.contains($0) || name.contains($0) }) { return false }
        if key.contains("_answered") || name.contains("answered") {
            // Aircall dit « décroché » dès que la messagerie répond : un appel de 21 s, c'est le répondeur, pas un
            // échange (retour d'Yves du 08/11/2026). Durée inconnue : on garde l'appel.
            guard let seconds = AircallLog.seconds(in: activity.note ?? "") else { return true }
            return seconds >= minimumCallSeconds
        }
        if ["call", "meeting", "google_agenda"].contains(key) { return true }
        if Label.matches(name, DebriefTemplate.typeName) || key.hasPrefix("call_effectu") { return true }
        return ["reunion", "rendez-vous", "rdv", "visio", "meeting"].contains { name.contains($0) }
    }

    /// Devis envoyé : type « Devis envoyé », ou texte au passé qui dit qu'un devis est parti (« devis TMA envoyé »,
    /// « devis renvoyé »). « Envoyer les devis » est une tâche à faire, même cochée : ce n'est pas la preuve d'un envoi
    /// (retour d'Yves du 08/11/2026).
    public static func isQuoteSent(_ activity: Activity, typeNames: [String: String]) -> Bool {
        guard activity.done else { return false }
        let name = typeNames[activity.type] ?? activity.type
        if Label.matches(name, "Devis envoyé") || activity.type.lowercased().hasPrefix("devis_envoy") { return true }
        let subject = Label.normalized(activity.subject)
        return subject.contains("devis") && subject.range(of: #"\br?envoye(?:e|s|es)?\b"#, options: .regularExpression) != nil
    }
}

extension LeadTagRules {
    static let signedRegex = try? NSRegularExpression(pattern: #"\bsign(?:é|ée|és|ées)\b"#, options: [.caseInsensitive])
    static let innerNegationRegex = try? NSRegularExpression(pattern: #"\b(?:pas|non|jamais|ni|aucun|aucune)\b|\bn['’]"#,
                                                             options: [.caseInsensitive])
    static let negationRegex = try? NSRegularExpression(pattern: #"\b(?:pas|non|jamais|plus|ni)\b[^.!?\n]{0,15}$"#,
                                                        options: [.caseInsensitive])

    /// Ligne qui dit qu'un devis / contrat est signé (« c'est signé pour SEO », « contrat signé »),
    /// sans négation juste avant (« pas encore signé ») ni question (« c'est signé ça ? ») ; nil sinon.
    /// « signer », « va signer » ne comptent pas.
    public static func signedExcerpt(in text: String) -> String? {
        guard let signedRegex else { return nil }
        return affirmativeExcerpt(of: signedRegex, in: text)
    }

    /// Phrase où `regex` trouve une affirmation : ni négation juste avant, ni point d'interrogation juste après.
    static func affirmativeExcerpt(of regex: NSRegularExpression, in text: String) -> String? {
        guard let negationRegex else { return nil }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let start = max(0, match.range.location - 25)
            let before = ns.substring(with: NSRange(location: start, length: match.range.location - start))
            if negationRegex.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) != nil {
                continue
            }
            // Négation au milieu de l'expression : « devis pas encore signé », « validons pas la proposition ».
            let matched = ns.substring(with: match.range)
            if innerNegationRegex?.firstMatch(in: matched, range: NSRange(location: 0, length: (matched as NSString).length)) != nil {
                continue
            }
            let end = NSMaxRange(match.range)
            let after = ns.substring(with: NSRange(location: end, length: min(20, ns.length - end)))
            if let stop = after.first(where: { "?.!\n".contains($0) }), stop == "?" { continue }
            let lineRange = ns.lineRange(for: match.range)
            // Ligne longue (début d'e-mail) : à partir du début de la phrase.
            var from = lineRange.location
            let head = NSRange(location: lineRange.location, length: match.range.location - lineRange.location)
            let stop = ns.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?"), options: .backwards, range: head)
            if NSMaxRange(lineRange) - from > 160, stop.location != NSNotFound { from = stop.location + 1 }
            let line = ns.substring(with: NSRange(location: from, length: NSMaxRange(lineRange) - from))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return line.count > 160 ? String(line.prefix(157)) + "…" : line
        }
        return nil
    }

    static let kickoffRegex = try? NSRegularExpression(
        pattern: #"\b(?:kick[- ]?off|onboarding)\b|\b(?:rdv|rendez-vous|réunion|reunion|call|point) de (?:lancement|démarrage|demarrage)\b"#,
        options: [.caseInsensitive])

    /// Lancement du projet (« rdv de lancement SEO effectué », « kickoff », « onboarding ») : le devis a été signé.
    public static func isKickoff(_ activity: Activity) -> Bool {
        guard activity.done, let kickoffRegex else { return false }
        let subject = activity.subject
        return kickoffRegex.firstMatch(in: subject, range: NSRange(location: 0, length: (subject as NSString).length)) != nil
    }
}

/// Filtre « Étiquettes » de la liste (demande d'Yves du 08/11/2026).
public enum TagFilter: String, CaseIterable, Sendable, Identifiable {
    case all, signing, quoteSent, quoteToDo, access, meeting, firstCall

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "Toutes"
        case .signing: return "En signature"
        case .quoteSent: return "Devis envoyé"
        case .quoteToDo: return "Devis à faire"
        case .access: return "Accès en attente"
        case .meeting: return "RDV à venir"
        case .firstCall: return "1er call à faire"
        }
    }

    public func matches(_ tags: LeadTags) -> Bool {
        switch self {
        case .all: return true
        case .signing: return tags.hasSigning
        case .quoteSent: return tags.hasPendingQuote
        case .quoteToDo: return tags.hasQuoteToDo
        case .access: return tags.hasAccessPending
        case .meeting: return tags.hasUpcomingMeeting
        case .firstCall: return tags.firstCallToDo
        }
    }
}

/// Filtre « Étiquettes » à choix multiple (demande d'Yves du 08/11/2026) : aucune étiquette choisie (ou « Toutes »)
/// = toutes les activités ; sinon les activités qui ont AU MOINS UNE des étiquettes choisies.
public extension Set where Element == TagFilter {
    var isAll: Bool { isEmpty || contains(.all) }

    func matches(_ tags: LeadTags) -> Bool {
        isAll || contains { $0 != .all && $0.matches(tags) }
    }

    /// « Toutes », « En signature », « En signature ou Devis envoyé »… (dans l'ordre du filtre).
    var label: String {
        isAll ? TagFilter.all.label : TagFilter.allCases.filter { $0 != .all && contains($0) }.map(\.label)
            .joined(separator: " ou ")
    }
}

/// Calcule les étiquettes d'une fiche à partir de Pipedrive (1 à 6 requêtes, faites quand la carte apparaît).
public struct LeadTagsLoader: Sendable {
    let client: PipedriveClient

    public init(client: PipedriveClient) {
        self.client = client
    }

    /// `myEmail` : mon adresse, dont le domaine désigne l'agence (e-mails de devis et de signature) ; sans elle,
    /// les e-mails de l'affaire ne sont pas lus.
    public func load(for item: ActivityItem, typeNames: [String: String], timeZone: TimeZone,
                     now: Date = Date(), myEmail: String? = nil) async throws -> LeadTags {
        let dealID = item.activity.dealID
        let personID = item.person?.id ?? item.activity.personID
        guard dealID != nil || personID != nil else { return .none }
        // Affaire perdue : pas d'étiquette. Affaire gagnée : signée (date de gain), donc pas d'étiquette non plus.
        if let deal = item.deal, deal.status == "lost" { return .none }
        // Analyse de Claude (champ « Devis en attente ») : elle fait foi pour les devis, devis par devis.
        let analysis = QuoteAnalysis(text: item.deal?.quoteAnalysis)
        if let analysis, analysis.coversQuotes {
            var firstCall = false
            if item.deal?.status != "won", analysis.entries(.signed).isEmpty {
                let check = try await conversation(dealID: dealID, personID: personID, typeNames: typeNames)
                firstCall = !check.spoke
            }
            return LeadTags(analysis: analysis, firstCallToDo: firstCall, now: now, timeZone: timeZone)
        }
        let local = try await localTags(for: item, dealID: dealID, personID: personID, typeNames: typeNames,
                                        timeZone: timeZone, now: now, myEmail: myEmail)
        guard let analysis else { return local }
        // Analyse sans partie devis (seulement des accès en attente ou des rendez-vous) : les devis restent cherchés par
        // l'app, les accès et rendez-vous viennent de l'analyse.
        return local.adding(access: analysis.quotes(.access, now: now, timeZone: timeZone),
                            meetings: analysis.entries(.meeting).compactMap { UpcomingMeeting(entry: $0, timeZone: timeZone) },
                            now: now, timeZone: timeZone)
    }

    /// Règles de l'app quand Claude n'a pas encore analysé les devis de l'affaire.
    func localTags(for item: ActivityItem, dealID: Int?, personID: Int?, typeNames: [String: String],
                   timeZone: TimeZone, now: Date, myEmail: String?) async throws -> LeadTags {
        if let deal = item.deal, deal.status == "won" {
            let day = deal.wonTime.flatMap(FrenchFormat.parseInstant).map { FrenchFormat.apiDay(from: $0, timeZone: timeZone) }
                ?? FrenchFormat.apiDay(from: now, timeZone: timeZone)
            return LeadTags(quotes: [], firstCallToDo: false, signature: SignatureEvidence(
                source: .dealWon, day: day, dateText: FrenchFormat.longDate(fromAPI: day, now: now, timeZone: timeZone),
                text: "Affaire marquée « Gagnée »"))
        }

        let check = try await conversation(dealID: dealID, personID: personID, typeNames: typeNames)
        let (spoke, dealDone, personDone, dealNotes) = (check.spoke, check.dealDone, check.personDone, check.dealNotes)

        // E-mails de l'affaire (sans bloquer les étiquettes si la lecture échoue).
        let ownDomain = myEmail.flatMap(DealMail.domain)
        var mails: [DealMail] = []
        if let dealID, ownDomain != nil {
            mails = (try? await client.dealMails(dealID: dealID)) ?? []
        }

        // Devis : activités de l'affaire (sans affaire, de la personne), puis e-mails de l'agence avec un devis joint.
        let quoteSource = dealID != nil ? dealDone : personDone
        let activityQuotes = quoteSource
            .filter { LeadTagRules.isQuoteSent($0, typeNames: typeNames) }
            .compactMap { activity -> QuoteSent? in
                guard let day = activity.localDay(timeZone: timeZone) else { return nil }
                let note = activity.note.map(PlainText.from(html:))?.trimmingCharacters(in: .whitespacesAndNewlines)
                return QuoteSent(id: activity.id, subject: activity.subject.isEmpty ? "Devis envoyé" : activity.subject,
                                 day: day, dateText: activity.displayDate(now: now),
                                 note: (note?.isEmpty ?? true) ? nil : note)
            }
        var mailQuotes: [QuoteSent] = []
        if let ownDomain {
            for mail in mails {
                guard let documents = MailRules.quoteDocuments(in: mail, ownDomain: ownDomain),
                      let day = mail.day(timeZone: timeZone), let sentAt = mail.sentAt else { continue }
                // Même devis que l'activité « Devis envoyé » du jour, ou renvoi du même fichier le même jour : une seule fois.
                if activityQuotes.contains(where: { $0.day == day }) { continue }
                if mailQuotes.contains(where: { $0.day == day && $0.note == "Pièce jointe : \(documents)" }) { continue }
                let instant = ISO8601DateFormatter().string(from: sentAt)
                mailQuotes.append(QuoteSent(id: mail.id, source: .mail, subject: mail.subject.isEmpty ? "E-mail" : mail.subject,
                                            day: day, dateText: FrenchFormat.longDate(fromAPI: instant, now: now, timeZone: timeZone),
                                            note: "Pièce jointe : \(documents)"))
            }
        }
        let allQuotes = activityQuotes + mailQuotes
        let today = FrenchFormat.apiDay(from: now, timeZone: timeZone)
        let quotes = allQuotes
            .filter { (LeadTags.daysBetween($0.day, today) ?? 0) <= LeadTags.pendingWindowDays }
            .sorted { $0.day != $1.day ? $0.day > $1.day : $0.id > $1.id }

        // Signature (seulement s'il y a un devis ou un champ « Contrat signé le ») : la preuve la plus récente.
        var evidences: [SignatureEvidence] = []
        if let signedDay = item.deal?.signedDate.map({ String($0.prefix(10)) }), FrenchFormat.dayParts(signedDay) != nil {
            evidences.append(SignatureEvidence(source: .signedField, day: signedDay,
                                               dateText: FrenchFormat.longDate(fromAPI: signedDay, now: now, timeZone: timeZone),
                                               text: "Contrat signé le \(FrenchFormat.date(fromAPI: signedDay))"))
        }
        if !allQuotes.isEmpty, let dealID {
            for activity in dealDone {
                guard let day = activity.localDay(timeZone: timeZone), !LeadTagRules.isQuoteSent(activity, typeNames: typeNames)
                else { continue }
                if LeadTagRules.isKickoff(activity) {
                    evidences.append(SignatureEvidence(source: .activity, day: day, dateText: activity.displayDate(now: now),
                                                       text: activity.subject))
                    continue
                }
                let text = activity.subject + "\n" + (activity.note.map(PlainText.from(html:)) ?? "")
                if let excerpt = LeadTagRules.signedExcerpt(in: text) {
                    evidences.append(SignatureEvidence(source: .activity, day: day, dateText: activity.displayDate(now: now),
                                                       text: excerpt))
                }
            }
            var notes = dealNotes ?? []
            if dealNotes == nil {
                notes = try await client.notes(filter: "deal_id", id: dealID, limit: 50)
            }
            // Comptes rendus Leexi exclus : « il a signé avec l'agence X » n'est pas notre devis.
            for note in notes where !note.isLeexi {
                guard let excerpt = LeadTagRules.signedExcerpt(in: PlainText.from(html: note.html)) else { continue }
                let day = note.date.map { FrenchFormat.apiDay(from: $0, timeZone: timeZone) } ?? String((note.addTime ?? "").prefix(10))
                guard FrenchFormat.dayParts(day) != nil else { continue }
                evidences.append(SignatureEvidence(source: .note, day: day, dateText: note.dateText(now: now), text: excerpt))
            }
            if let ownDomain {
                for mail in mails {
                    guard let excerpt = MailRules.signatureExcerpt(in: mail, ownDomain: ownDomain),
                          let day = mail.day(timeZone: timeZone), let sentAt = mail.sentAt else { continue }
                    let instant = ISO8601DateFormatter().string(from: sentAt)
                    evidences.append(SignatureEvidence(source: .mail, day: day,
                                                       dateText: FrenchFormat.longDate(fromAPI: instant, now: now, timeZone: timeZone),
                                                       text: excerpt))
                }
            }
        }
        let signature = evidences.max { $0.day < $1.day }
        // Une signature (même ancienne) prouve qu'on s'est déjà parlé : pas de « 1er call à faire ».
        return LeadTags(quotes: quotes, firstCallToDo: !spoke && signature == nil, signature: signature)
    }

    /// Échange de vive voix déjà eu : activités terminées de l'affaire, puis de la personne, puis notes Leexi.
    func conversation(dealID: Int?, personID: Int?, typeNames: [String: String]) async throws
        -> (spoke: Bool, dealDone: [Activity], personDone: [Activity], dealNotes: [PipedriveNote]?) {
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
        var dealNotes: [PipedriveNote]?
        if !spoke, let dealID {
            dealNotes = try await client.notes(filter: "deal_id", id: dealID, limit: 50)
            spoke = dealNotes?.contains(where: \.isLeexi) ?? false
        }
        if !spoke, let personID {
            spoke = try await client.notes(filter: "person_id", id: personID, limit: 50).contains(where: \.isLeexi)
        }
        return (spoke, dealDone, personDone, dealNotes)
    }
}

/// Rendez-vous à venir avec le contact (demande d'Yves du 09/11/2026 : « des fois j'ai une alerte et j'oublie que j'ai un
/// rendez-vous à venir »). Trouvé dans Google Agenda par l'analyse de Claude (section `RDV À VENIR`), ou dans les
/// activités Pipedrive de type rendez-vous (agenda synchronisé, « meeting »).
public struct UpcomingMeeting: Hashable, Sendable {
    public enum Source: String, Hashable, Sendable {
        case calendar
        case pipedrive
    }

    public let title: String
    /// Jour à l'heure de Paris (AAAA-MM-JJ).
    public let day: String
    /// Heure de Paris (« 14:00 »), nil si toute la journée.
    public let time: String?
    public let detail: String?
    public let source: Source

    public init(title: String, day: String, time: String?, detail: String? = nil, source: Source) {
        self.title = title
        self.day = day
        self.time = time
        self.detail = detail
        self.source = source
    }

    /// Ligne `RDV À VENIR` de l'analyse de Claude.
    init?(entry: QuoteAnalysis.Entry, timeZone: TimeZone) {
        guard let day = entry.day else { return nil }
        self.init(title: entry.title, day: day, time: entry.time, detail: entry.detail, source: .calendar)
    }

    /// Activité Pipedrive pas encore faite, de type rendez-vous (« meeting », agenda synchronisé, « RDV », visio…).
    public init?(activity: Activity, typeNames: [String: String], timeZone: TimeZone) {
        guard !activity.done, Self.isMeeting(activity, typeNames: typeNames),
              let day = activity.localDay(timeZone: timeZone) else { return nil }
        self.init(title: activity.subject, day: day, time: Reschedule.parisTime(of: activity, timeZone: timeZone),
                  source: .pipedrive)
    }

    static func isMeeting(_ activity: Activity, typeNames: [String: String]) -> Bool {
        let key = activity.type.lowercased()
        if ["meeting", "google_agenda"].contains(key) { return true }
        let name = Label.normalized(typeNames[activity.type] ?? "")
        return ["rendez-vous", "rdv", "reunion", "visio", "meeting", "agenda"].contains { name.contains($0) }
    }

    /// Moment du rendez-vous (fin de journée s'il n'a pas d'heure : il reste « à venir » toute la journée).
    func instant(timeZone: TimeZone) -> Date? {
        guard let parts = FrenchFormat.dayParts(day) else { return nil }
        let clock = (time ?? "23:59").split(separator: ":").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day,
                                                  hour: clock.first ?? 23, minute: clock.last ?? 59))
    }

    /// Rendez-vous pas encore passés, le plus proche d'abord, sans doublon (même jour et même heure).
    public static func upcoming(_ meetings: [UpcomingMeeting], now: Date = Date(), timeZone: TimeZone) -> [UpcomingMeeting] {
        var seen = Set<String>()
        return meetings
            .compactMap { meeting in meeting.instant(timeZone: timeZone).map { (meeting, $0) } }
            .filter { $0.1 >= now }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
            .filter { seen.insert("\($0.day) \($0.time ?? "")").inserted }
    }

    /// « jeu. 12 novembre à 14:00 ».
    public func dateText(now: Date = Date(), timeZone: TimeZone) -> String {
        let date = Reschedule.dateText(day, now: now, timeZone: timeZone)
        return time.map { "\(date) à \($0)" } ?? date
    }

    /// « auj. », « demain », « dans 3j ».
    public func countdown(now: Date = Date(), timeZone: TimeZone) -> String? {
        guard let days = LeadTags.daysBetween(FrenchFormat.apiDay(from: now, timeZone: timeZone), day) else { return nil }
        switch days {
        case ..<1: return "auj."
        case 1: return "demain"
        default: return "dans \(days)j"
        }
    }
}
