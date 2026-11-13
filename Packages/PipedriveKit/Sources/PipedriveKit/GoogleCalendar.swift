import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Bouton « Créer un RDV » (demande d'Yves du 13/11/2026) : l'app crée elle-même le rendez-vous dans son Google Agenda,
/// invite le contact (Google envoie l'invitation) avec un lien Google Meet, puis ouvre le brouillon du mail de
/// confirmation dans Superhuman.
///
/// Connexion Google : OAuth 2.0 d'un client « iOS » (avec PKCE, sans secret). L'identifiant du client n'est pas secret :
/// Yves le colle dans Réglages (rien en dur dans ce dépôt public). Le jeton de renouvellement reste au trousseau.
/// Portée la plus étroite possible : `calendar.events` (créer des événements, rien d'autre).
public enum GoogleOAuth {
    public static let scope = "https://www.googleapis.com/auth/calendar.events"
    static let authorizeEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    static let revokeEndpoint = "https://oauth2.googleapis.com/revoke"

    /// Identifiant d'un client OAuth Google : « 1234-abcd.apps.googleusercontent.com ». Retrouvé aussi dans un texte
    /// collé plus long (fichier de la console, guillemets, espaces) ou sous sa forme « à l'envers »
    /// (« com.googleusercontent.apps.1234-abcd ») : retour d'Yves du 13/11/2026, le bouton restait grisé.
    public static func validClientID(_ text: String) -> String? {
        let cleaned = text.replacingOccurrences(of: #"\s"#, with: "", options: .regularExpression)
        if let range = cleaned.range(of: #"[0-9]+-[A-Za-z0-9_]+\.apps\.googleusercontent\.com"#,
                                     options: [.regularExpression, .caseInsensitive]) {
            return cleaned[range].lowercased()
        }
        if let range = cleaned.range(of: #"com\.googleusercontent\.apps\.[0-9]+-[A-Za-z0-9_]+"#,
                                     options: [.regularExpression, .caseInsensitive]) {
            let id = cleaned[range].dropFirst("com.googleusercontent.apps.".count)
            return (id + ".apps.googleusercontent.com").lowercased()
        }
        return nil
    }

    /// Pourquoi le texte saisi n'est pas un ID client (une adresse e-mail est l'erreur la plus probable).
    public static func clientIDProblem(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Collez d'abord l'ID client Google." }
        if trimmed.contains("@") {
            return "Ce champ attend l'ID client Google, pas votre adresse e-mail : console Google Cloud › Identifiants › ID client OAuth (type iOS), il se termine par « .apps.googleusercontent.com »."
        }
        return "Ce n'est pas un ID client Google : il ressemble à « 1234-abcd.apps.googleusercontent.com » (console Google Cloud › Identifiants › ID client OAuth de type iOS)."
    }

    /// Schéma de retour d'un client iOS : l'identifiant « à l'envers » (« com.googleusercontent.apps.1234-abcd »).
    public static func callbackScheme(clientID: String) -> String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    public static func redirectURI(clientID: String) -> String {
        callbackScheme(clientID: clientID) + ":/oauth2redirect"
    }

    /// Page de connexion Google (PKCE S256 : `codeChallenge` = base64url(SHA-256(vérificateur)), calculé par l'app).
    public static func authorizationURL(clientID: String, codeChallenge: String, state: String,
                                        loginHint: String? = nil) -> URL? {
        var components = URLComponents(string: authorizeEndpoint)
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI(clientID: clientID)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // Toujours un jeton de renouvellement, même après une 1re connexion.
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        if let loginHint, !loginHint.isEmpty { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        components?.queryItems = items
        return components?.url
    }

    /// Code d'autorisation lu dans l'adresse de retour (l'état doit être celui envoyé).
    public static func authorizationCode(from callback: URL, state: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { throw GoogleCalendarError.authorizationDenied(error) }
        guard value("state") == state, let code = value("code"), !code.isEmpty else {
            throw GoogleCalendarError.invalidCallback
        }
        return code
    }
}

public enum GoogleCalendarError: Error, Equatable, LocalizedError, Sendable {
    case notConfigured
    case authorizationDenied(String)
    case invalidCallback
    /// Jeton de renouvellement refusé (révoqué, expiré) : il faut se reconnecter dans Réglages.
    case reconnectNeeded
    case rejected(status: Int, message: String?)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google Agenda n'est pas connecté : Réglages › Google Agenda."
        case .authorizationDenied(let reason):
            return reason == "access_denied" ? "Connexion Google annulée." : "Google a refusé la connexion (\(reason))."
        case .invalidCallback:
            return "Réponse de Google illisible : réessayez la connexion."
        case .reconnectNeeded:
            return "La connexion Google a expiré : reconnectez Google Agenda dans Réglages."
        case .rejected(let status, let message):
            return message.map { "Google Agenda : \($0)" } ?? "Google Agenda a refusé la demande (code \(status))."
        }
    }
}

/// Jetons Google (le jeton d'accès dure environ une heure ; le jeton de renouvellement n'arrive qu'à la connexion).
public struct GoogleTokens: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Encore utilisable dans une minute.
    public func isValid(now: Date = Date()) -> Bool { expiresAt.timeIntervalSince(now) > 60 }
}

/// Rendez-vous à créer.
public struct MeetingRequest: Sendable, Equatable {
    public let title: String
    public let start: Date
    public let minutes: Int
    public let attendeeEmail: String
    public let withMeet: Bool
    public let description: String?

    public init(title: String, start: Date, minutes: Int, attendeeEmail: String, withMeet: Bool, description: String?) {
        self.title = title
        self.start = start
        self.minutes = minutes
        self.attendeeEmail = attendeeEmail
        self.withMeet = withMeet
        self.description = description
    }

    /// Corps de `POST calendars/primary/events` (heure de Paris).
    func body(timeZone: TimeZone, requestID: String) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        var body: [String: Any] = [
            "summary": title,
            "start": ["dateTime": formatter.string(from: start), "timeZone": timeZone.identifier],
            "end": ["dateTime": formatter.string(from: end), "timeZone": timeZone.identifier],
            "attendees": [["email": attendeeEmail]],
            "reminders": ["useDefault": true],
        ]
        if let description, !description.isEmpty { body["description"] = description }
        if withMeet {
            body["conferenceData"] = [
                "createRequest": ["requestId": requestID, "conferenceSolutionKey": ["type": "hangoutsMeet"]],
            ]
        }
        return body
    }
}

/// Rendez-vous créé : lien vers l'événement et, s'il y en a un, lien de la visio Google Meet.
public struct CreatedMeeting: Sendable, Equatable {
    public let id: String
    public let htmlLink: String?
    public let meetLink: String?

    public init(id: String, htmlLink: String?, meetLink: String?) {
        self.id = id
        self.htmlLink = htmlLink
        self.meetLink = meetLink
    }
}

/// Appels à Google (jetons OAuth, création d'événement). Lecture et écriture seulement sur un clic d'Yves.
public struct GoogleCalendarClient: Sendable {
    public let clientID: String
    let transport: any HTTPTransport

    public init(clientID: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.clientID = clientID
        self.transport = transport
    }

    /// Échange le code reçu après la connexion contre les jetons.
    public func exchange(code: String, codeVerifier: String, now: Date = Date()) async throws -> GoogleTokens {
        try await token([
            ("client_id", clientID),
            ("code", code),
            ("code_verifier", codeVerifier),
            ("grant_type", "authorization_code"),
            ("redirect_uri", GoogleOAuth.redirectURI(clientID: clientID)),
        ], now: now)
    }

    /// Nouveau jeton d'accès à partir du jeton de renouvellement.
    public func refresh(refreshToken: String, now: Date = Date()) async throws -> GoogleTokens {
        do {
            return try await token([
                ("client_id", clientID),
                ("grant_type", "refresh_token"),
                ("refresh_token", refreshToken),
            ], now: now)
        } catch GoogleCalendarError.rejected(let status, _) where status == 400 || status == 401 {
            throw GoogleCalendarError.reconnectNeeded
        }
    }

    /// Révoque l'accès (déconnexion dans Réglages) ; une erreur n'empêche pas la déconnexion locale.
    public func revoke(token: String) async {
        guard var components = URLComponents(string: GoogleOAuth.revokeEndpoint) else { return }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        _ = try? await transport.send(request)
    }

    /// Crée le rendez-vous dans l'agenda principal et envoie l'invitation (`sendUpdates=all`).
    public func createEvent(_ meeting: MeetingRequest, accessToken: String, timeZone: TimeZone,
                            requestID: String = UUID().uuidString) async throws -> CreatedMeeting {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")
        components?.queryItems = [
            URLQueryItem(name: "sendUpdates", value: "all"),
            URLQueryItem(name: "conferenceDataVersion", value: meeting.withMeet ? "1" : "0"),
        ]
        guard let url = components?.url else { throw GoogleCalendarError.invalidCallback }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: meeting.body(timeZone: timeZone, requestID: requestID))
        request.timeoutInterval = 30
        let json = try await send(request)
        guard let id = json["id"].stringValue else { throw GoogleCalendarError.rejected(status: 200, message: nil) }
        var meet = json["hangoutLink"].stringValue
        if meet == nil, let points = json["conferenceData"]["entryPoints"].arrayValue {
            meet = points.first { $0["entryPointType"].stringValue == "video" }?["uri"].stringValue
        }
        return CreatedMeeting(id: id, htmlLink: json["htmlLink"].stringValue, meetLink: meet)
    }

    private func token(_ fields: [(String, String)], now: Date) async throws -> GoogleTokens {
        guard let url = URL(string: GoogleOAuth.tokenEndpoint) else { throw GoogleCalendarError.invalidCallback }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(fields.map { "\($0.0)=\(ActionLinks.percentEncode($0.1))" }.joined(separator: "&").utf8)
        request.timeoutInterval = 30
        let json = try await send(request)
        guard let access = json["access_token"].stringValue else { throw GoogleCalendarError.invalidCallback }
        let seconds = json["expires_in"].doubleValue ?? 3_600
        return GoogleTokens(accessToken: access, refreshToken: json["refresh_token"].stringValue,
                            expiresAt: now.addingTimeInterval(seconds))
    }

    private func send(_ request: URLRequest) async throws -> JSONValue {
        let (data, response) = try await transport.send(request)
        let json = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
        guard (200..<300).contains(response.statusCode) else {
            let message = json["error"]["message"].stringValue ?? json["error_description"].stringValue
            throw GoogleCalendarError.rejected(status: response.statusCode, message: message)
        }
        return json
    }
}

/// Textes du rendez-vous et du mail de confirmation (demande d'Yves du 13/11/2026 : sujet « Rendez-vous le … à … »,
/// « Comme convenu au téléphone, je viens de vous envoyer une invitation pour un rendez-vous le … à … »).
public enum MeetingInvite {
    public static let durations = [30, 45, 60]

    /// Titre par défaut, comme les rendez-vous d'Yves : « call CHIC CHAM / YATEO ».
    public static func defaultTitle(client: String) -> String {
        "call \(client.uppercased(with: Locale(identifier: "fr_FR"))) / YATEO"
    }

    /// Prochain jour ouvré à 10:00 (heure de Paris) : point de départ du choix de la date.
    public static func defaultStart(now: Date = Date(), timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var day = calendar.startOfDay(for: now)
        repeat {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        } while calendar.isDateInWeekend(day)
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
    }

    /// « jeudi 19 novembre à 10:00 » (année seulement si ce n'est pas l'année en cours).
    public static func when(_ start: Date, now: Date = Date(), timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        let text = FrenchFormat.longDate(fromAPI: formatter.string(from: start), now: now, timeZone: timeZone,
                                         weekday: true)
        // Rendez-vous à minuit (rare) : on garde l'heure, contrairement aux autres dates de l'app.
        return text.contains(" à ") ? text : text + " à 00:00"
    }

    public static func mailSubject(start: Date, now: Date = Date(), timeZone: TimeZone) -> String {
        "Rendez-vous le \(when(start, now: now, timeZone: timeZone))"
    }

    /// Corps du brouillon (Superhuman ajoute la signature d'Yves).
    public static func mailBody(contactName: String?, start: Date, meetLink: String?, now: Date = Date(),
                                timeZone: TimeZone) -> String {
        let firstName = contactName?.split(separator: " ").first.map(String.init)
        var lines = [firstName.map { "Bonjour \($0)," } ?? "Bonjour,", ""]
        lines.append("Comme convenu au téléphone, je viens de vous envoyer une invitation pour un rendez-vous le "
                     + "\(when(start, now: now, timeZone: timeZone)).")
        if let meetLink, !meetLink.isEmpty {
            lines += ["", "Lien de la visio : \(meetLink)"]
        }
        lines += ["", "À très vite,"]
        return lines.joined(separator: "\n")
    }
}
