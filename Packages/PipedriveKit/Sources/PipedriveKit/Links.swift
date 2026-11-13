import Foundation

/// Liens qui ouvrent les autres apps (téléphone, Aircall, OnOff, WhatsApp, Superhuman, Pipedrive).
public enum ActionLinks {
    public static let defaultOnOffTemplate = "onoff://call?number={numero}"
    public static let defaultSuperhumanTemplate = "https://mail.superhuman.com/{compte}/thread/{fil}"

    public static func phoneCall(_ e164: String) -> URL? {
        URL(string: "tel:" + e164)
    }

    /// Schéma documenté par Aircall : aircall://call?to=<numéro E.164>.
    public static func aircall(_ e164: String) -> URL? {
        URL(string: "aircall://call?to=" + e164)
    }

    /// Lien OnOff à partir d'un modèle réglable ({numero} = +33…, {numero_sans_plus} = 33…).
    public static func onoff(_ e164: String, template: String) -> URL? {
        let digits = e164.hasPrefix("+") ? String(e164.dropFirst()) : e164
        let link = template
            .replacingOccurrences(of: "{numero_sans_plus}", with: digits)
            .replacingOccurrences(of: "{numero}", with: e164)
        return URL(string: link)
    }

    public static func sms(_ e164: String) -> URL? {
        URL(string: "sms:" + e164)
    }

    /// Lance un raccourci iPhone (app Raccourcis) avec le numéro en entrée : solution pour OnOff.
    public static func shortcut(named name: String, text: String) -> URL? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "shortcuts://run-shortcut?name=\(percentEncode(cleaned))&input=text&text=\(percentEncode(text))")
    }

    /// Schémas de lien possibles pour l'app OnOff (aucun n'est documenté) : détectés sur l'iPhone.
    public static let onoffCandidateSchemes = [
        "onoff", "onoffapp", "onoff-app", "onoffnumbers", "onoff-numbers", "onofftelecom",
        "onoff-telecom", "onoffcall", "onoffcalls", "onoffbusiness", "onoff-business", "ootelecom",
        // L'app s'affiche « Number » sur l'iPhone d'Yves (Onoff Numbers, éditeur ONOFFAPP).
        "number", "numbers", "numberapp", "number-app", "onoffnumber", "onoff-number", "onoffnumbersapp", "com.onoffapp.onoff", "com.onoffapp.numbers", "com.onoffapp", "com.onoff.app", "com.onoff", "onoffmobile", "onoff-mobile", "onoffapp-ios", "onoffios", "com.onoffapp.app", "com.onoffapp.app.ios",
    ]

    /// Schéma d'un modèle de lien : « onoff://call?… » → « onoff ».
    public static func scheme(ofTemplate template: String) -> String? {
        guard let range = template.range(of: "://") else { return nil }
        let scheme = template[..<range.lowerBound].lowercased()
        return scheme.isEmpty ? nil : scheme
    }

    public static func whatsapp(_ e164: String) -> URL? {
        let digits = e164.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return URL(string: "https://wa.me/" + digits)
    }

    /// Brouillon d'e-mail (ouvert dans l'app de messagerie par défaut, Superhuman si elle est choisie dans Réglages).
    /// Un « % » dans le sujet (« devis (1100/12%) ») vidait le sujet dans Superhuman, qui décode le lien deux fois
    /// (retour d'Yves du 13/11/2026) : il est remplacé par « ％ » (signe pour cent pleine chasse, identique à l'œil).
    public static func mailto(to address: String, subject: String? = nil, body: String? = nil) -> URL? {
        let subject = subject?.replacingOccurrences(of: "%", with: "％")
        let cleaned = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.contains("@"), !cleaned.contains(" ") else { return nil }
        var link = "mailto:" + percentEncode(cleaned, keeping: "@.+-_")
        var query: [String] = []
        if let subject, !subject.isEmpty { query.append("subject=" + percentEncode(subject)) }
        if let body, !body.isEmpty { query.append("body=" + percentEncode(body)) }
        if !query.isEmpty { link += "?" + query.joined(separator: "&") }
        return URL(string: link)
    }

    /// Fil Superhuman à partir d'un modèle réglable ({compte} = votre adresse, {fil} = identifiant Gmail du fil).
    public static func superhumanThread(account: String, threadID: String, template: String) -> URL? {
        let link = template
            .replacingOccurrences(of: "{compte}", with: percentEncode(account, keeping: "@.+-_"))
            .replacingOccurrences(of: "{fil}", with: percentEncode(threadID))
        return URL(string: link)
    }

    public static func pipedriveOrganization(domain: String, id: Int) -> URL? {
        URL(string: "https://\(domain).pipedrive.com/organization/\(id)")
    }

    public static func pipedrivePerson(domain: String, id: Int) -> URL? {
        URL(string: "https://\(domain).pipedrive.com/person/\(id)")
    }

    /// Fiche Pipedrive (ouvre l'app Pipedrive si elle est installée) : l'affaire, sinon la personne, sinon la société.
    public static func pipedrive(domain: String, dealID: Int?, personID: Int?, orgID: Int?) -> URL? {
        let base = "https://\(domain).pipedrive.com"
        if let dealID { return URL(string: "\(base)/deal/\(dealID)") }
        if let personID { return URL(string: "\(base)/person/\(personID)") }
        if let orgID { return URL(string: "\(base)/organization/\(orgID)") }
        return nil
    }

    /// Encodage strict : seuls lettres, chiffres et « -._~ » (plus `keeping`) restent tels quels.
    static func percentEncode(_ text: String, keeping extra: String = "") -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        allowed.insert(charactersIn: extra)
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
