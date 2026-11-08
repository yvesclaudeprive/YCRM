import Foundation

/// E-mail synchronisé sur une affaire (v1 `/deals/{id}/mailMessages`), réduit à ce qui sert aux étiquettes.
public struct DealMail: Hashable, Sendable {
    public let id: Int
    public let subject: String
    /// Début du message, sans la citation du message précédent (« Le 3 nov. 2026 à 21:14, X a écrit : … »).
    public let snippet: String
    /// Adresses de l'expéditeur (en minuscules).
    public let from: [String]
    /// Destinataires et copies (en minuscules).
    public let recipients: [String]
    public let hasAttachments: Bool
    /// Noms des pièces jointes (hors images intégrées au message).
    public let attachmentNames: [String]
    public let sentAt: Date?

    public init(id: Int, subject: String, snippet: String, from: [String], recipients: [String], hasAttachments: Bool,
                attachmentNames: [String], sentAt: Date?) {
        self.id = id
        self.subject = subject
        self.snippet = Self.withoutQuote(snippet)
        self.from = from.map { $0.lowercased() }
        self.recipients = recipients.map { $0.lowercased() }
        self.hasAttachments = hasAttachments
        self.attachmentNames = attachmentNames
        self.sentAt = sentAt
    }

    init?(json: JSONValue) {
        let data = json["data"].isNull ? json : json["data"]
        // Brouillons : jamais envoyés.
        guard let id = data["id"].intValue, !(data["draft_flag"].boolValue ?? false) else { return nil }
        func addresses(_ key: String) -> [String] {
            (data[key].arrayValue ?? []).compactMap { $0["email_address"].stringValue }
        }
        let names = (data["attachments"].arrayValue ?? [])
            .filter { !($0["inline_flag"].boolValue ?? false) }
            .compactMap { $0["name"].stringValue }
        self.init(id: id, subject: data["subject"].stringValue ?? "", snippet: data["snippet"].stringValue ?? "",
                  from: addresses("from"), recipients: addresses("to") + addresses("cc"),
                  hasAttachments: (data["has_real_attachments_flag"].boolValue ?? false) || !names.isEmpty,
                  attachmentNames: names, sentAt: data["message_time"].stringValue.flatMap(FrenchFormat.parseInstant))
    }

    static let quoteStart = try? NSRegularExpression(
        pattern: #"(?:\b(?:Le|On)\s.{4,90}?\s(?:a écrit|wrote)\s*:|-{3,}|_{5,}|\bDe\s*:\s|\bFrom\s*:\s)"#,
        options: [.caseInsensitive])

    /// Coupe la citation du message précédent : une réponse « Merci ! » ne reprend pas la signature d'un ancien message.
    static func withoutQuote(_ text: String) -> String {
        let ns = text as NSString
        guard let match = quoteStart?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return text }
        return ns.substring(to: match.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func domain(_ email: String) -> String? {
        guard let at = email.lastIndex(of: "@") else { return nil }
        let domain = email[email.index(after: at)...].lowercased()
        return domain.isEmpty ? nil : domain
    }

    /// Envoyé par quelqu'un de l'agence (même domaine que moi).
    func isFromAgency(_ ownDomain: String) -> Bool {
        from.contains { Self.domain($0) == ownDomain }
    }

    /// Au moins un destinataire hors de l'agence (le client).
    func hasExternalRecipient(_ ownDomain: String) -> Bool {
        recipients.contains { Self.domain($0).map { $0 != ownDomain } ?? false }
    }

    /// Jour d'envoi à l'heure de Paris (AAAA-MM-JJ).
    func day(timeZone: TimeZone) -> String? {
        sentAt.map { FrenchFormat.apiDay(from: $0, timeZone: timeZone) }
    }
}

/// Règles de lecture des e-mails de l'affaire pour l'étiquette « Devis envoyé » (demande d'Yves du 08/11/2026 :
/// un devis envoyé par mail sans activité « Devis envoyé » doit compter ; une signature écrite par mail aussi).
public enum MailRules {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "bmp", "ics"]

    static let quoteWords = try? NSRegularExpression(
        pattern: #"\b(?:devis|proposition|propale|offre|bon de commande|bdc|contrat)\b"#, options: [.caseInsensitive])

    static func matches(_ regex: NSRegularExpression?, _ text: String) -> Bool {
        guard let regex else { return false }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// Devis envoyé par e-mail : écrit par l'agence (même domaine que moi) à au moins un destinataire extérieur,
    /// avec une pièce jointe « Proposition_… », « Devis… », « Bon de commande… », « Contrat… »
    /// (ou, sans nom de pièce jointe connu, un objet / début de message qui parle d'un devis).
    /// Renvoie le nom des pièces jointes concernées (ou l'objet) ; nil sinon. Une facture, un audit ne comptent pas.
    public static func quoteDocuments(in mail: DealMail, ownDomain: String) -> String? {
        let own = ownDomain.lowercased()
        guard mail.hasAttachments, mail.isFromAgency(own), mail.hasExternalRecipient(own) else { return nil }
        let documents = mail.attachmentNames.filter { name in
            let ext = (name as NSString).pathExtension.lowercased()
            return !imageExtensions.contains(ext)
        }
        if !documents.isEmpty {
            let quotes = documents.filter { name in
                let words = Label.normalized(name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " "))
                return matches(quoteWords, words) && !words.hasPrefix("facture")
            }
            return quotes.isEmpty ? nil : quotes.joined(separator: ", ")
        }
        guard mail.attachmentNames.isEmpty else { return nil }
        let text = Label.normalized(mail.subject + " " + mail.snippet)
        return text.range(of: #"\b(?:devis|proposition|propale)\b"#, options: .regularExpression) != nil ? mail.subject : nil
    }

    /// Signature écrite par n'importe qui (souvent le mail de facturation de l'agence) :
    /// « À la suite de la signature du bon de commande », « Les documents ont été signés ».
    static let signedByAnyone = try? NSRegularExpression(pattern: [
        #"\b[àa] la suite de (?:la|votre) signature\b"#,
        #"\bsuite [àa] (?:la|votre) signature\b"#,
        #"\b(?:ont|a) (?:bien )?été sign(?:é|ée|és|ées)\b"#,
        #"\b(?:j'ai|j’ai|nous avons) (?:bien )?sign(?:é|ée|és|ées)\b"#,
    ].joined(separator: "|"), options: [.caseInsensitive])

    /// Accord écrit par le client seulement (« Bon pour accord » peut figurer dans le mail d'envoi de l'agence).
    static let agreedByClient = try? NSRegularExpression(pattern: [
        #"\bbon pour accord\b"#,
        #"\b(?:nous )?validons\b[^.!?\n]{0,40}\b(?:proposition|devis|offre|bon de commande)"#,
        #"\bje valide\b[^.!?\n]{0,40}\b(?:proposition|devis|offre|bon de commande)"#,
        #"\b(?:devis|proposition|offre|bon de commande)\b[^.!?\n]{0,25}\b(?:validée?s?|acceptée?s?|signée?s?)\b"#,
    ].joined(separator: "|"), options: [.caseInsensitive])

    /// E-mail qui prouve une signature ; renvoie la phrase concernée (nil sinon). Négations et questions exclues
    /// (« pas encore signé », « c'est signé ça ? »).
    public static func signatureExcerpt(in mail: DealMail, ownDomain: String) -> String? {
        let text = mail.subject + "\n" + mail.snippet
        let fromClient = !mail.from.isEmpty && !mail.isFromAgency(ownDomain.lowercased())
        let regexes = fromClient ? [signedByAnyone, agreedByClient] : [signedByAnyone]
        for regex in regexes.compactMap({ $0 }) {
            if let excerpt = LeadTagRules.affirmativeExcerpt(of: regex, in: text) { return excerpt }
        }
        return nil
    }
}
