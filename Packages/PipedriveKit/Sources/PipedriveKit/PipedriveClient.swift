import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PipedriveConfiguration: Sendable, Equatable {
    /// Sous-domaine de l'entreprise : « exemple » pour https://exemple.pipedrive.com.
    public let companyDomain: String
    /// Jeton API personnel. Fourni par le trousseau de l'iPhone, jamais écrit dans le code.
    public let apiToken: String

    public init(companyDomain: String, apiToken: String) {
        self.companyDomain = companyDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.apiToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isValidDomain(_ domain: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty && normalized.count <= 63 && normalized.allSatisfy { allowed.contains($0) }
            && !normalized.hasPrefix("-") && !normalized.hasSuffix("-")
    }

    var baseURL: URL? {
        guard Self.isValidDomain(companyDomain) else { return nil }
        return URL(string: "https://\(companyDomain).pipedrive.com")
    }
}

/// Transport HTTP, remplaçable dans les tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), http))
                } else {
                    continuation.resume(throwing: PipedriveError.invalidResponse)
                }
            }
            task.resume()
        }
    }
}

/// Accès à l'API REST Pipedrive (v2 ; v1 pour l'utilisateur courant, les types d'activité et les e-mails).
public struct PipedriveClient: Sendable {
    public let configuration: PipedriveConfiguration
    let transport: any HTTPTransport

    public init(configuration: PipedriveConfiguration, transport: any HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    // MARK: Compte

    /// Titulaire du jeton (vérifie aussi que le jeton est valide).
    public func currentUser() async throws -> PipedriveUser {
        let response = try await send("GET", "/api/v1/users/me")
        guard let user = PipedriveUser(json: response["data"]) else { throw PipedriveError.invalidResponse }
        return user
    }

    /// Utilisateurs du compte (filtre « Utilisateurs »).
    public func users() async throws -> [PipedriveUser] {
        let response = try await send("GET", "/api/v1/users")
        return (response["data"].arrayValue ?? []).compactMap(PipedriveUser.init(json:))
    }

    // MARK: Champs

    /// Champs des affaires (pour retrouver le code du champ « Score priorisation »).
    public func dealFields() async throws -> [FieldDefinition] {
        do {
            var fields: [FieldDefinition] = []
            var cursor: String?
            repeat {
                var query = [URLQueryItem(name: "limit", value: "500")]
                if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
                let response = try await send("GET", "/api/v2/dealFields", query: query)
                fields += (response["data"].arrayValue ?? []).compactMap(FieldDefinition.init(v2:))
                cursor = response["additional_data"]["next_cursor"].stringValue
            } while cursor != nil
            return fields
        } catch PipedriveError.notFound {
            let response = try await send("GET", "/api/v1/dealFields", query: [URLQueryItem(name: "limit", value: "500")])
            return (response["data"].arrayValue ?? []).compactMap(FieldDefinition.init(v1:))
        }
    }

    // MARK: Activités

    /// Activités non terminées d'un utilisateur, de la plus ancienne à la plus récente.
    /// `untilDay` (AAAA-MM-JJ) arrête la lecture dès qu'on le dépasse (marge d'un jour pour le fuseau horaire).
    public func openActivities(ownerID: Int, untilDay: String?) async throws -> [Activity] {
        var activities: [Activity] = []
        var cursor: String?
        let stopAfter = untilDay.flatMap { FrenchFormat.date(fromAPIDay: $0, timeZone: TimeZone(identifier: "UTC")!) }
            .map { FrenchFormat.apiDay(from: $0.addingTimeInterval(86_400), timeZone: TimeZone(identifier: "UTC")!) }
        repeat {
            var query = [
                URLQueryItem(name: "owner_id", value: String(ownerID)),
                URLQueryItem(name: "done", value: "false"),
                URLQueryItem(name: "sort_by", value: "due_date"),
                URLQueryItem(name: "sort_direction", value: "asc"),
                URLQueryItem(name: "limit", value: "500"),
            ]
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let response = try await send("GET", "/api/v2/activities", query: query)
            let page = (response["data"].arrayValue ?? []).compactMap(Activity.init(json:))
            activities += page
            cursor = response["additional_data"]["next_cursor"].stringValue
            if let stopAfter, let last = page.last?.dueDate, last > stopAfter { break }
        } while cursor != nil
        return activities
    }

    /// Crée une activité terminée (ex. « Répondeur ON/OFF ») datée de `date`, liée à l'affaire, la société et la personne.
    public func createDoneActivity(type: ActivityType, subject: String, date: Date, ownerID: Int?,
                                   dealID: Int?, orgID: Int?, personID: Int?, note: String? = nil) async throws -> Int {
        var body = Self.doneActivityBody(type: type, subject: subject, date: date, ownerID: ownerID,
                                         dealID: dealID, orgID: orgID, personID: personID)
        if let note, !note.isEmpty { body["note"] = .string(note) }
        let data = try JSONEncoder().encode(JSONValue.object(body))
        let response = try await send("POST", "/api/v2/activities", body: data)
        guard let id = response["data"]["id"].intValue else { throw PipedriveError.invalidResponse }
        return id
    }

    /// Corps de création : date et heure en UTC, comme l'attend Pipedrive.
    static func doneActivityBody(type: ActivityType, subject: String, date: Date, ownerID: Int?,
                                 dealID: Int?, orgID: Int?, personID: Int?) -> [String: JSONValue] {
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        var body: [String: JSONValue] = [
            "subject": .string(subject),
            "type": .string(type.key),
            "done": .bool(true),
            "due_date": .string(FrenchFormat.apiDay(from: date, timeZone: utc)),
            "due_time": .string(String(format: "%02ld:%02ld", parts.hour ?? 0, parts.minute ?? 0)),
        ]
        if let ownerID { body["owner_id"] = .int(ownerID) }
        if let dealID { body["deal_id"] = .int(dealID) }
        if let orgID { body["org_id"] = .int(orgID) }
        if let personID { body["participants"] = .array([.object(["person_id": .int(personID), "primary": .bool(true)])]) }
        return body
    }

    /// Supprime une activité (bouton « Annuler » juste après une création par erreur).
    public func deleteActivity(id: Int) async throws {
        _ = try await send("DELETE", "/api/v2/activities/\(id)")
    }

    /// Décale une alerte (bouton « Décaler ») : nouvelle échéance au format Pipedrive (jour et heure en UTC ;
    /// sans heure, l'heure est effacée).
    public func rescheduleActivity(id: Int, dueDate: String, dueTime: String?) async throws {
        let body: [String: JSONValue] = ["due_date": .string(dueDate), "due_time": dueTime.map(JSONValue.string) ?? .null]
        let data = try JSONEncoder().encode(JSONValue.object(body))
        _ = try await send("PATCH", "/api/v2/activities/\(id)", body: data)
    }

    public func activityTypes() async throws -> [ActivityType] {
        let response = try await send("GET", "/api/v1/activityTypes")
        return (response["data"].arrayValue ?? []).compactMap(ActivityType.init(json:))
    }

    // MARK: Affaires, personnes, sociétés (par lots de 100)

    public func deals(ids: [Int], scoreCode: String?, signedCode: String? = nil,
                      analysisCode: String? = nil) async throws -> [DealSummary] {
        var extra: [URLQueryItem] = []
        let codes = [scoreCode, signedCode, analysisCode].compactMap { $0 }
        if !codes.isEmpty { extra.append(URLQueryItem(name: "custom_fields", value: codes.joined(separator: ","))) }
        return try await batch("/api/v2/deals", ids: ids, extra: extra).compactMap {
            DealSummary(json: $0, scoreCode: scoreCode, signedCode: signedCode, analysisCode: analysisCode)
        }
    }

    /// Note sur une affaire (ou, sans affaire, sur la personne) : « Note pour Claude » écrite depuis l'app.
    public func addNote(content: String, dealID: Int?, personID: Int?, orgID: Int?) async throws -> Int {
        var body: [String: JSONValue] = ["content": .string(content)]
        if let dealID { body["deal_id"] = .int(dealID) }
        if dealID == nil, let personID { body["person_id"] = .int(personID) }
        if dealID == nil, personID == nil, let orgID { body["org_id"] = .int(orgID) }
        guard body.count > 1 else { throw PipedriveError.validation("Aucune affaire, personne ni société pour la note") }
        let data = try JSONEncoder().encode(JSONValue.object(body))
        let response = try await send("POST", "/api/v1/notes", body: data)
        guard let id = response["data"]["id"].intValue else { throw PipedriveError.invalidResponse }
        return id
    }

    /// Supprime une note (bouton « Annuler » juste après l'envoi).
    public func deleteNote(id: Int) async throws {
        _ = try await send("DELETE", "/api/v1/notes/\(id)")
    }

    public func persons(ids: [Int]) async throws -> [PersonContact] {
        try await batch("/api/v2/persons", ids: ids).compactMap(PersonContact.init(json:))
    }

    /// « Autres contacts » de la fenêtre des numéros (demande d'Yves du 13/11/2026) : les contacts de la société,
    /// sans la personne déjà affichée, par ordre alphabétique.
    public func persons(organizationID: Int, excluding personID: Int? = nil) async throws -> [PersonContact] {
        let response = try await send("GET", "/api/v2/persons", query: [
            URLQueryItem(name: "org_id", value: String(organizationID)),
            URLQueryItem(name: "limit", value: "100"),
        ])
        return (response["data"].arrayValue ?? [])
            .compactMap(PersonContact.init(json:))
            .filter { $0.id != personID }
            .sorted { Label.normalized($0.name) < Label.normalized($1.name) }
    }

    /// Noms des sociétés, par identifiant.
    public func organizationNames(ids: [Int]) async throws -> [Int: String] {
        var names: [Int: String] = [:]
        for json in try await batch("/api/v2/organizations", ids: ids) {
            if let id = json["id"].intValue, let name = json["name"].stringValue { names[id] = name }
        }
        return names
    }

    func batch(_ path: String, ids: [Int], extra: [URLQueryItem] = []) async throws -> [JSONValue] {
        let unique = Array(Set(ids)).sorted()
        var results: [JSONValue] = []
        var start = 0
        while start < unique.count {
            let chunk = unique[start..<min(start + 100, unique.count)]
            let query = [URLQueryItem(name: "ids", value: chunk.map(String.init).joined(separator: ",")),
                         URLQueryItem(name: "limit", value: "100")] + extra
            let response = try await send("GET", path, query: query)
            results += response["data"].arrayValue ?? []
            start += 100
        }
        return results
    }

    // MARK: Historique (notes et activités liées)

    /// Notes (v1) d'une affaire, personne ou société, les plus récentes d'abord.
    public func notes(filter: String, id: Int, limit: Int = 40) async throws -> [PipedriveNote] {
        let response = try await send("GET", "/api/v1/notes", query: [
            URLQueryItem(name: filter, value: String(id)),
            URLQueryItem(name: "sort", value: "add_time DESC"),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        return (response["data"].arrayValue ?? []).compactMap(PipedriveNote.init(json:))
    }

    /// Activités d'une affaire, personne ou société, les plus récentes d'abord ; `done` : seulement faites / à faire.
    public func activities(filter: String, id: Int, limit: Int = 200, done: Bool? = nil) async throws -> [Activity] {
        var query = [
            URLQueryItem(name: filter, value: String(id)),
            URLQueryItem(name: "sort_by", value: "due_date"),
            URLQueryItem(name: "sort_direction", value: "desc"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let done { query.append(URLQueryItem(name: "done", value: done ? "true" : "false")) }
        let response = try await send("GET", "/api/v2/activities", query: query)
        return (response["data"].arrayValue ?? []).compactMap(Activity.init(json:))
    }

    // MARK: E-mails synchronisés

    /// Dernier e-mail **du client** ou **envoyé par moi au client** (jamais celui d'un collègue), le plus récent des deux,
    /// avec l'identifiant Gmail du fil pour Superhuman.
    public func lastMail(personID: Int, clientEmails: [String], myEmail: String?) async throws -> MailHint? {
        let response = try await send("GET", "/api/v1/persons/\(personID)/mailMessages", query: [
            URLQueryItem(name: "start", value: "0"), URLQueryItem(name: "limit", value: "50"),
        ])
        let messages = response["data"].arrayValue ?? []
        guard let chosen = messages.first(where: { Self.isBetweenMeAndClient($0, clientEmails: clientEmails, myEmail: myEmail) }),
              let latest = MailHint(message: chosen) else { return nil }
        guard let threadID = latest.pipedriveThreadID else { return latest }
        // Le fil Gmail porte l'identifiant de son premier message.
        let thread = try? await send("GET", "/api/v1/mailbox/mailThreads/\(threadID)/mailMessages")
        let threadMessages = thread?["data"].arrayValue ?? []
        let oldest = threadMessages.min { ($0["message_time"].stringValue ?? "") < ($1["message_time"].stringValue ?? "") }
        let threadGmailID = oldest.flatMap { MailHint.gmailID(fromStoragePath: $0["s3_bucket_path"].stringValue ?? $0["body_url"].stringValue) }
        return MailHint(subject: latest.subject, pipedriveThreadID: threadID, gmailMessageID: threadGmailID ?? latest.gmailMessageID)
    }

    /// E-mails synchronisés d'une affaire, les plus récents d'abord (devis envoyés par mail, signatures).
    public func dealMails(dealID: Int, limit: Int = 50) async throws -> [DealMail] {
        let response = try await send("GET", "/api/v1/deals/\(dealID)/mailMessages", query: [
            URLQueryItem(name: "start", value: "0"), URLQueryItem(name: "limit", value: String(limit)),
        ])
        return (response["data"].arrayValue ?? []).compactMap(DealMail.init(json:))
    }

    /// Message écrit par le client, ou par moi à destination du client (destinataire ou copie).
    static func isBetweenMeAndClient(_ json: JSONValue, clientEmails: [String], myEmail: String?) -> Bool {
        let data = json["data"].isNull ? json : json["data"]
        func addresses(_ key: String) -> Set<String> {
            Set((data[key].arrayValue ?? []).compactMap { $0["email_address"].stringValue?.lowercased() })
        }
        let client = Set(clientEmails.map { $0.lowercased() })
        let from = addresses("from")
        if !from.isDisjoint(with: client) { return true }
        guard let me = myEmail?.lowercased(), !me.isEmpty, from.contains(me) else { return false }
        return !addresses("to").union(addresses("cc")).isDisjoint(with: client)
    }

    // MARK: Requêtes

    func makeRequest(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        guard !configuration.apiToken.isEmpty else { throw PipedriveError.missingToken }
        guard let baseURL = configuration.baseURL,
              var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw PipedriveError.invalidDomain }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw PipedriveError.invalidDomain }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        // Jeton dans un en-tête (jamais dans l'URL, qui peut finir dans des journaux).
        request.setValue(configuration.apiToken, forHTTPHeaderField: "x-api-token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> JSONValue {
        let request = try makeRequest(method, path, query: query, body: body)
        let (data, response) = try await transport.send(request)
        let json = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
        switch response.statusCode {
        case 200..<300:
            guard json["success"].boolValue != false else {
                throw PipedriveError.server(status: response.statusCode, message: json["error"].stringValue)
            }
            return json
        case 401: throw PipedriveError.unauthorized
        case 403: throw PipedriveError.forbidden
        case 404: throw PipedriveError.notFound
        case 429: throw PipedriveError.rateLimited
        default: throw PipedriveError.server(status: response.statusCode, message: json["error"].stringValue)
        }
    }
}
