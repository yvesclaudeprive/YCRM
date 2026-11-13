import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PipedriveKit

/// Bouton « Créer un RDV » (demande d'Yves du 13/11/2026). Identifiants et adresses fictifs.
final class GoogleCalendarTests: XCTestCase {
    let clientID = "123456-abcdef.apps.googleusercontent.com"

    func instant(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }

    func testClientIDAndRedirect() {
        XCTAssertEqual(GoogleOAuth.validClientID("  \(clientID) "), clientID)
        XCTAssertNil(GoogleOAuth.validClientID("pas un identifiant"))
        XCTAssertNil(GoogleOAuth.validClientID("https://exemple.com"))
        XCTAssertEqual(GoogleOAuth.callbackScheme(clientID: clientID), "com.googleusercontent.apps.123456-abcdef")
        XCTAssertEqual(GoogleOAuth.redirectURI(clientID: clientID), "com.googleusercontent.apps.123456-abcdef:/oauth2redirect")
    }

    func testAuthorizationURLAndCallback() throws {
        let url = try XCTUnwrap(GoogleOAuth.authorizationURL(clientID: clientID, codeChallenge: "defi", state: "etat-1",
                                                              loginHint: "moi@example.com"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(url.host, "accounts.google.com")
        XCTAssertEqual(value("scope"), "https://www.googleapis.com/auth/calendar.events", "portée la plus étroite")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge"), "defi")
        XCTAssertEqual(value("redirect_uri"), "com.googleusercontent.apps.123456-abcdef:/oauth2redirect")
        XCTAssertEqual(value("login_hint"), "moi@example.com")

        let callback = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123456-abcdef:/oauth2redirect?state=etat-1&code=CODE-9"))
        XCTAssertEqual(try GoogleOAuth.authorizationCode(from: callback, state: "etat-1"), "CODE-9")
        XCTAssertThrowsError(try GoogleOAuth.authorizationCode(from: callback, state: "autre-etat"))
        let denied = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123456-abcdef:/oauth2redirect?error=access_denied&state=etat-1"))
        XCTAssertThrowsError(try GoogleOAuth.authorizationCode(from: denied, state: "etat-1")) { error in
            XCTAssertEqual(error as? GoogleCalendarError, .authorizationDenied("access_denied"))
        }
    }

    func testExchangeAndCreateEvent() async throws {
        let transport = MockTransport([
            "POST /token": .init(status: 200, body: #"{"access_token":"acces-1","expires_in":3599,"refresh_token":"renouv-1","token_type":"Bearer"}"#),
            "POST /calendar/v3/calendars/primary/events": .init(status: 200, body: #"""
            {"id":"evt-1","htmlLink":"https://www.google.com/calendar/event?eid=abc","hangoutLink":"https://meet.google.com/aaa-bbbb-ccc"}
            """#),
        ])
        let client = GoogleCalendarClient(clientID: clientID, transport: transport)
        let now = try instant("2026-11-13T10:00:00Z")
        let tokens = try await client.exchange(code: "CODE-9", codeVerifier: "verif", now: now)
        XCTAssertEqual(tokens.accessToken, "acces-1")
        XCTAssertEqual(tokens.refreshToken, "renouv-1")
        XCTAssertTrue(tokens.isValid(now: now))
        XCTAssertFalse(tokens.isValid(now: now.addingTimeInterval(3_590)))

        let start = try instant("2026-11-19T09:00:00Z") // jeudi 19 novembre à 10:00 (Paris)
        let meeting = MeetingRequest(title: "call ENTREPRISE ALPHA / YATEO", start: start, minutes: 30,
                                     attendeeEmail: "client@example.com", withMeet: true, description: "Fiche : lien")
        let created = try await client.createEvent(meeting, accessToken: tokens.accessToken, timeZone: paris, requestID: "req-1")
        XCTAssertEqual(created, CreatedMeeting(id: "evt-1", htmlLink: "https://www.google.com/calendar/event?eid=abc",
                                               meetLink: "https://meet.google.com/aaa-bbbb-ccc"))

        let recorded = await transport.recorded
        let tokenRequest = try XCTUnwrap(recorded.first { $0.url?.path == "/token" })
        let form = String(data: tokenRequest.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(form.contains("grant_type=authorization_code"))
        XCTAssertTrue(form.contains("code_verifier=verif"))
        XCTAssertFalse(form.contains("client_secret"), "client iOS : jamais de secret")

        let eventRequest = try XCTUnwrap(recorded.first { $0.url?.path.hasSuffix("/events") == true })
        XCTAssertEqual(eventRequest.value(forHTTPHeaderField: "Authorization"), "Bearer acces-1")
        XCTAssertEqual(query(eventRequest, "sendUpdates"), "all", "Google envoie l'invitation au contact")
        XCTAssertEqual(query(eventRequest, "conferenceDataVersion"), "1")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: eventRequest.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["summary"] as? String, "call ENTREPRISE ALPHA / YATEO")
        XCTAssertEqual((body["start"] as? [String: Any])?["dateTime"] as? String, "2026-11-19T10:00:00+01:00")
        XCTAssertEqual((body["end"] as? [String: Any])?["dateTime"] as? String, "2026-11-19T10:30:00+01:00")
        XCTAssertEqual((body["start"] as? [String: Any])?["timeZone"] as? String, "Europe/Paris")
        XCTAssertEqual((body["attendees"] as? [[String: Any]])?.first?["email"] as? String, "client@example.com")
        let conference = (body["conferenceData"] as? [String: Any])?["createRequest"] as? [String: Any]
        XCTAssertEqual((conference?["conferenceSolutionKey"] as? [String: Any])?["type"] as? String, "hangoutsMeet")
    }

    func testRefreshRefusedAsksToReconnect() async throws {
        let transport = MockTransport([
            "POST /token": .init(status: 400, body: #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#),
        ])
        let client = GoogleCalendarClient(clientID: clientID, transport: transport)
        do {
            _ = try await client.refresh(refreshToken: "ancien")
            XCTFail("un jeton refusé doit demander une reconnexion")
        } catch {
            XCTAssertEqual(error as? GoogleCalendarError, .reconnectNeeded)
        }
    }

    func testMeetingTexts() throws {
        let now = try instant("2026-11-13T10:00:00Z") // vendredi 13 novembre
        let start = try instant("2026-11-19T09:00:00Z")
        XCTAssertEqual(MeetingInvite.defaultTitle(client: "Entreprise Alpha"), "call ENTREPRISE ALPHA / YATEO")
        XCTAssertEqual(MeetingInvite.when(start, now: now, timeZone: paris), "jeudi 19 novembre à 10:00")
        XCTAssertEqual(MeetingInvite.mailSubject(start: start, now: now, timeZone: paris),
                       "Rendez-vous le jeudi 19 novembre à 10:00")
        XCTAssertEqual(MeetingInvite.mailBody(contactName: "Camille Test", start: start,
                                              meetLink: "https://meet.google.com/aaa-bbbb-ccc", now: now, timeZone: paris),
                       """
                       Bonjour Camille,

                       Comme convenu au téléphone, je viens de vous envoyer une invitation pour un rendez-vous le jeudi 19 novembre à 10:00.

                       Lien de la visio : https://meet.google.com/aaa-bbbb-ccc

                       À très vite,
                       """)
        XCTAssertTrue(MeetingInvite.mailBody(contactName: nil, start: start, meetLink: nil, now: now, timeZone: paris)
            .hasPrefix("Bonjour,\n\nComme convenu"))
        // Vendredi → lundi 10:00 (jamais un week-end).
        XCTAssertEqual(MeetingInvite.defaultStart(now: now, timeZone: paris), try instant("2026-11-16T09:00:00Z"))
    }
}
