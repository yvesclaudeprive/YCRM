import Foundation

/// Analyse des devis écrite par Claude deux fois par jour dans le champ d'affaire « Devis en attente »
/// (demande d'Yves du 08/11/2026) : devis par devis, ce qui est en signature, envoyé, signé ou abandonné.
/// Format lisible dans Pipedrive (une ligne par devis : titre | date JJ/MM/AAAA | détail) :
///
///     EN SIGNATURE
///     • Montée de version | 14/10/2026 | DocuSign consulté par le client le 15/10/2026
///     DEVIS ENVOYÉS
///     • Refonte du site | 16/04/2026 | relancé le 03/11/2026, rien de signé
///     DEVIS À FAIRE
///     • Audit SEO | 28/10/2026 | demandé par le client en rendez-vous, promis pour le 15/11
///     SIGNÉS
///     • TMA | 11/08/2026 | projet signé (yntranet)
///     ABANDONNÉS
///     • Audit SEO | 02/02/2026 | refusé par mail le 10/02/2026
///     ACCÈS EN ATTENTE
///     • FTP + back-office | 09/07/2026 | demandés par Mehdi, relancés le 05/11/2026
///     COMMENTAIRES
///     • 08/11/2026 : « la TMA est signée, la refonte non » → pris en compte
///     Analyse Claude du 08/11/2026 à 13:17
///
/// Champ vide = affaire pas encore analysée : l'app applique alors ses propres règles (`LeadTagsLoader`).
public struct QuoteAnalysis: Hashable, Sendable {
    public enum Status: String, CaseIterable, Hashable, Sendable {
        /// Envoyé en signature (DocuSign, bon de commande) et pas encore signé : le plus chaud.
        case signing
        /// Devis envoyé, en attente de réponse.
        case sent
        /// Le client attend un devis qui n'est pas encore parti (demande d'Yves du 08/11/2026) : étiquette « Devis à faire ».
        case toDo
        case signed
        case abandoned
        /// Accès demandés au client (FTP, back-office, Google Ads, GA…) et pas encore reçus (demande d'Yves du
        /// 08/11/2026) : ce n'est pas un devis, mais une étiquette « Accès » à part.
        case access
        /// Rendez-vous à venir avec le contact, trouvé dans Google Agenda (demande d'Yves du 09/11/2026) :
        /// « • call BEABA / YATEO | 12/11/2026 à 14:00 | avec Lina ».
        case meeting

        public var title: String {
            switch self {
            case .signing: return "En signature"
            case .sent: return "Devis envoyés"
            case .toDo: return "Devis à faire"
            case .signed: return "Signés"
            case .abandoned: return "Abandonnés"
            case .access: return "Accès en attente"
            case .meeting: return "RDV à venir"
            }
        }
    }

    public struct Entry: Hashable, Sendable {
        public let status: Status
        public let title: String
        /// Date de la ligne (AAAA-MM-JJ) : envoi du devis, envoi en signature ou signature.
        public let day: String?
        public let detail: String?
        /// Heure de Paris (« 14:00 ») si la date en donne une (« 12/11/2026 à 14:00 ») : rendez-vous.
        public let time: String?

        public init(status: Status, title: String, day: String?, detail: String?, time: String? = nil) {
            self.status = status
            self.title = title
            self.day = day
            self.detail = detail
            self.time = time
        }
    }

    /// Lignes, triées par statut puis de la plus récente à la plus ancienne.
    public let entries: [Entry]
    /// Commentaires d'Yves pris en compte (« 08/11/2026 : … → pris en compte »).
    public let comments: [String]
    /// « Analyse Claude du 08/11/2026 à 13:17 ».
    public let footer: String?
    public let text: String

    public func entries(_ status: Status) -> [Entry] { entries.filter { $0.status == status } }

    /// nil si le champ est vide (affaire pas encore analysée).
    public init?(text: String?) {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.text = text
        var section: Status?
        var inComments = false
        var entries: [Entry] = []
        var comments: [String] = []
        var footer: String?
        let lines = text.replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        for rawLine in lines {
            let line = Self.withoutBullet(rawLine)
            guard !line.isEmpty else { continue }
            // Une ligne à puce n'est jamais un titre de section (« • Devis envoyé » reste un devis).
            let bulleted = line != rawLine.trimmingCharacters(in: .whitespaces)
            let key = Self.headerKey(line)
            if !bulleted, key.hasPrefix("analyse claude") {
                footer = line
                continue
            }
            if !bulleted, let status = Self.sections[key] {
                section = status
                inComments = false
                continue
            }
            if !bulleted, Self.commentHeaders.contains(key) {
                section = nil
                inComments = true
                continue
            }
            if inComments {
                comments.append(line)
                continue
            }
            guard let section, !Self.emptyMarkers.contains(key) else { continue }
            entries.append(Self.entry(line, status: section))
        }
        let order = Status.allCases
        self.entries = entries.enumerated().sorted { lhs, rhs in
            let (a, b) = (lhs.element, rhs.element)
            if a.status != b.status {
                return order.firstIndex(of: a.status)! < order.firstIndex(of: b.status)!
            }
            if a.day != b.day { return (a.day ?? "") > (b.day ?? "") }
            return lhs.offset < rhs.offset
        }.map(\.element)
        self.comments = comments
        self.footer = footer
    }

    static let sections: [String: Status] = [
        "en signature": .signing, "en cours de signature": .signing, "envoyes en signature": .signing,
        "devis envoyes": .sent, "devis envoye": .sent, "devis en attente": .sent, "envoyes": .sent,
        "signes": .signed, "signe": .signed, "devis signes": .signed,
        "abandonnes": .abandoned, "abandonne": .abandoned, "perdus": .abandoned, "refuses": .abandoned,
        "acces en attente": .access, "demandes d'acces": .access, "acces demandes": .access,
        "devis a faire": .toDo, "a faire": .toDo, "devis attendus": .toDo, "devis demandes": .toDo,
        "rdv a venir": .meeting, "rendez-vous a venir": .meeting, "rendez-vous": .meeting, "rdv": .meeting,
    ]
    static let commentHeaders: Set<String> = ["commentaires", "commentaire", "commentaires d'yves"]
    static let emptyMarkers: Set<String> = ["aucun", "aucune", "rien", "neant", "-"]

    static func withoutBullet(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        while let first = text.first, "•-–*◦▪·".contains(first) {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    /// Titre de section normalisé : « DEVIS ENVOYÉS (2) : » → « devis envoyes ».
    static func headerKey(_ line: String) -> String {
        var key = Label.normalized(line)
        key = key.replacingOccurrences(of: #"\s*\(\d+\)"#, with: "", options: .regularExpression)
        key = key.trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        return key
    }

    static func entry(_ line: String, status: Status) -> Entry {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 2 {
            let day = apiDay(in: parts[1])
            let detail = parts.dropFirst(day == nil ? 1 : 2).joined(separator: " | ")
            return Entry(status: status, title: parts[0], day: day, detail: detail.isEmpty ? nil : detail,
                         time: day == nil ? nil : clock(in: parts[1]))
        }
        return Entry(status: status, title: line, day: apiDay(in: line), detail: nil)
    }

    /// Heure « 14:00 » / « 14h00 » / « 9h30 » du texte, au format « HH:MM ».
    static func clock(in text: String) -> String? {
        guard let range = text.range(of: #"\b\d{1,2}[:h]\d{2}\b"#, options: .regularExpression) else { return nil }
        let pieces = text[range].split(whereSeparator: { $0 == ":" || $0 == "h" }).compactMap { Int($0) }
        guard pieces.count == 2, (0...23).contains(pieces[0]), (0...59).contains(pieces[1]) else { return nil }
        return String(format: "%02ld:%02ld", pieces[0], pieces[1])
    }

    /// Première date « JJ/MM/AAAA » du texte, au format « AAAA-MM-JJ ».
    static func apiDay(in text: String) -> String? {
        guard let range = text.range(of: #"\b\d{1,2}/\d{1,2}/\d{4}\b"#, options: .regularExpression) else { return nil }
        let pieces = text[range].split(separator: "/").compactMap { Int($0) }
        guard pieces.count == 3, (1...12).contains(pieces[1]), (1...31).contains(pieces[0]) else { return nil }
        return String(format: "%04ld-%02ld-%02ld", pieces[2], pieces[1], pieces[0])
    }

    /// Devis de la ligne pour l'étiquette et la fenêtre de détail.
    func quotes(_ status: Status, now: Date, timeZone: TimeZone) -> [QuoteSent] {
        entries(status).enumerated().map { index, entry in
            QuoteSent(id: index, source: .analysis, subject: entry.title, day: entry.day ?? "",
                      dateText: entry.day.map { FrenchFormat.longDate(fromAPI: $0, now: now, timeZone: timeZone) } ?? "",
                      note: entry.detail)
        }
    }
}

/// « Note pour Claude » écrite depuis l'app (demande d'Yves du 08/11/2026) : une note Pipedrive sur l'affaire, que
/// l'analyse de Claude lit au passage suivant pour corriger l'affaire **ou** sa façon de détecter les devis.
public enum ClaudeNote {
    public static let prefix = "Pour Claude (YCRM) :"

    /// Contenu HTML de la note : préfixe, texte échappé, retours à la ligne.
    public static func html(_ text: String) -> String {
        let escaped = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
        return "<b>\(prefix)</b> \(escaped)"
    }
}
