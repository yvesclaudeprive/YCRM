import Foundation
import Observation
import PipedriveKit

let parisTimeZone = TimeZone(identifier: "Europe/Paris") ?? .current

private enum StorageKeys {
    static let keychainService = "com.yateo.ycrm"
    static let token = "pipedrive-api-token"
    static let domain = "pipedrive-company-domain"
    static let userID = "pipedrive-user-id"
    static let myEmail = "my-email"
    static let onoffTemplate = "onoff-link-template"
    static let superhumanTemplate = "superhuman-link-template"
    static let onoffMethod = "onoff-method"
    static let onoffShortcut = "onoff-shortcut-name"
    static let claudeFireURL = "claude-fire-url"
    static let claudeToken = "claude-routine-token"
}

/// Façon de lancer un appel OnOff (aucun lien officiel n'existe).
enum OnOffMethod: String, CaseIterable, Identifiable {
    case link
    case shortcut
    /// Number (OnOff) choisi comme app d'appel par défaut de l'iPhone : un lien tel: l'ouvre sur le numéro.
    case defaultCallingApp

    var id: String { rawValue }
    var label: String {
        switch self {
        case .link: return "Lien"
        case .shortcut: return "Raccourci"
        case .defaultCallingApp: return "App par défaut"
        }
    }
}

/// Connexion Pipedrive et réglages (le jeton reste dans le trousseau ; le reste n'est pas secret).
@MainActor
@Observable
final class AppSession {
    private(set) var companyDomain: String
    private(set) var hasToken: Bool
    private(set) var userID: Int?
    private(set) var myEmail: String
    private(set) var onoffTemplate: String
    private(set) var superhumanTemplate: String
    private(set) var onoffMethod: OnOffMethod
    private(set) var onoffShortcutName: String
    /// Adresse de déclenchement de la tâche Claude « Note pour Claude » (pas secrète ; le jeton est au trousseau).
    private(set) var claudeFireURL: String
    private(set) var hasClaudeToken: Bool

    private let keychain: KeychainStore
    private let defaults = UserDefaults.standard

    init() {
        let store = KeychainStore(service: StorageKeys.keychainService)
        keychain = store
        companyDomain = defaults.string(forKey: StorageKeys.domain) ?? ""
        hasToken = !(store.read(StorageKeys.token) ?? "").isEmpty
        let savedID = defaults.integer(forKey: StorageKeys.userID)
        userID = savedID > 0 ? savedID : nil
        // Aucune adresse en dur (dépôt public) : e-mail lu dans Pipedrive (`users/me`) à la connexion.
        myEmail = defaults.string(forKey: StorageKeys.myEmail) ?? ""
        onoffTemplate = defaults.string(forKey: StorageKeys.onoffTemplate) ?? ActionLinks.defaultOnOffTemplate
        superhumanTemplate = defaults.string(forKey: StorageKeys.superhumanTemplate) ?? ActionLinks.defaultSuperhumanTemplate
        onoffMethod = defaults.string(forKey: StorageKeys.onoffMethod).flatMap(OnOffMethod.init(rawValue:)) ?? .link
        onoffShortcutName = defaults.string(forKey: StorageKeys.onoffShortcut) ?? "YCRM OnOff"
        claudeFireURL = defaults.string(forKey: StorageKeys.claudeFireURL) ?? ""
        hasClaudeToken = !(store.read(StorageKeys.claudeToken) ?? "").isEmpty
    }

    /// Claude prévenu en temps réel des « Notes pour Claude » : adresse et jeton enregistrés.
    var isClaudeTriggerReady: Bool { hasClaudeToken && ClaudeTrigger.validURL(claudeFireURL) != nil }

    /// Déclencheur de la tâche Claude, nil s'il n'est pas configuré.
    func makeClaudeTrigger() -> ClaudeTrigger? {
        guard let token = keychain.read(StorageKeys.claudeToken) else { return nil }
        return try? ClaudeTrigger(fireURL: claudeFireURL, token: token)
    }

    /// Enregistre l'adresse de déclenchement et, s'il est saisi, le jeton (trousseau). Jeton vide = on garde l'ancien.
    func saveClaudeTrigger(fireURL: String, token: String) throws {
        guard let url = ClaudeTrigger.validURL(fireURL) else { throw ClaudeTrigger.TriggerError.invalidURL }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            try keychain.save(token, account: StorageKeys.claudeToken)
            hasClaudeToken = true
        }
        guard hasClaudeToken else { throw ClaudeTrigger.TriggerError.missingToken }
        claudeFireURL = url.absoluteString
        defaults.set(claudeFireURL, forKey: StorageKeys.claudeFireURL)
    }

    func removeClaudeTrigger() {
        keychain.delete(StorageKeys.claudeToken)
        defaults.removeObject(forKey: StorageKeys.claudeFireURL)
        claudeFireURL = ""
        hasClaudeToken = false
    }

    func makeClient() throws -> PipedriveClient {
        guard let token = keychain.read(StorageKeys.token), !token.isEmpty else { throw PipedriveError.missingToken }
        return PipedriveClient(configuration: PipedriveConfiguration(companyDomain: companyDomain, apiToken: token))
    }

    /// Vérifie le jeton auprès de Pipedrive (lecture seule) puis l'enregistre dans le trousseau.
    func connect(domain: String, token: String) async throws {
        let configuration = PipedriveConfiguration(companyDomain: domain, apiToken: token)
        guard PipedriveConfiguration.isValidDomain(configuration.companyDomain) else { throw PipedriveError.invalidDomain }
        guard !configuration.apiToken.isEmpty else { throw PipedriveError.missingToken }
        let me = try await PipedriveClient(configuration: configuration).currentUser()
        try keychain.save(configuration.apiToken, account: StorageKeys.token)
        companyDomain = configuration.companyDomain
        userID = me.id
        defaults.set(configuration.companyDomain, forKey: StorageKeys.domain)
        defaults.set(me.id, forKey: StorageKeys.userID)
        if myEmail.isEmpty, let email = me.email, !email.isEmpty {
            myEmail = email
            defaults.set(email, forKey: StorageKeys.myEmail)
        }
        hasToken = true
    }

    /// Identifiant Pipedrive du titulaire du jeton (filtre « mes activités »).
    /// Complète aussi l'e-mail s'il n'est pas encore connu.
    func ensureUserID() async throws -> Int {
        if let userID, !myEmail.isEmpty { return userID }
        let me = try await makeClient().currentUser()
        userID = me.id
        defaults.set(me.id, forKey: StorageKeys.userID)
        if myEmail.isEmpty, let email = me.email, !email.isEmpty {
            myEmail = email
            defaults.set(email, forKey: StorageKeys.myEmail)
        }
        return me.id
    }

    func savePreferences(myEmail: String, onoffTemplate: String, superhumanTemplate: String,
                         onoffMethod: OnOffMethod, onoffShortcutName: String) {
        let email = myEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let onoff = onoffTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let superhuman = superhumanTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        self.myEmail = email
        self.onoffTemplate = onoff.isEmpty ? ActionLinks.defaultOnOffTemplate : onoff
        self.superhumanTemplate = superhuman.isEmpty ? ActionLinks.defaultSuperhumanTemplate : superhuman
        defaults.set(self.myEmail, forKey: StorageKeys.myEmail)
        defaults.set(self.onoffTemplate, forKey: StorageKeys.onoffTemplate)
        defaults.set(self.superhumanTemplate, forKey: StorageKeys.superhumanTemplate)
        self.onoffMethod = onoffMethod
        let shortcut = onoffShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.onoffShortcutName = shortcut.isEmpty ? "YCRM OnOff" : shortcut
        defaults.set(onoffMethod.rawValue, forKey: StorageKeys.onoffMethod)
        defaults.set(self.onoffShortcutName, forKey: StorageKeys.onoffShortcut)
    }

    func disconnect() {
        keychain.delete(StorageKeys.token)
        defaults.removeObject(forKey: StorageKeys.userID)
        userID = nil
        hasToken = false
    }
}
