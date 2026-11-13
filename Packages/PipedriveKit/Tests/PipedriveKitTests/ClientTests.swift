import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PipedriveKit

final class ClientTests: XCTestCase {
    let config = PipedriveConfiguration(companyDomain: "test", apiToken: "jeton-factice")

    func feedTransport() -> MockTransport {
        MockTransport([
            "GET /api/v2/activities": .init(status: 200, body: Fixtures.activities),
            "GET /api/v2/dealFields": .init(status: 200, body: Fixtures.dealFields),
            "GET /api/v2/deals": .init(status: 200, body: Fixtures.deals),
            "GET /api/v2/persons": .init(status: 200, body: Fixtures.persons),
            "GET /api/v2/organizations": .init(status: 200, body: Fixtures.organizations),
        ])
    }

    func testFeedIsFilteredEnrichedAndSortedByScore() async throws {
        let transport = feedTransport()
        let loader = ActivityFeedLoader(client: PipedriveClient(configuration: config, transport: transport))
        let filter = ActivityDateFilter(from: nil, to: "2026-11-07")
        let items = try await loader.load(ownerIDs: [7], filter: filter, timeZone: paris, now: Self.seventhNoon)

        XCTAssertEqual(items.map(\.id), [2, 1, 3], "score 87, puis 42,5, puis sans score ; l'activité future est exclue")
        XCTAssertEqual(items[0].organizationName, "Entreprise Gamma", "société retrouvée par l'affaire")
        XCTAssertEqual(items[0].person?.name, "Bruno Test")
        XCTAssertEqual(items[0].score, 87)
        XCTAssertEqual(items[1].phoneNumbers.map(\.e164), ["+33611223344", "+33123456789"])
        XCTAssertEqual(items[1].mobileNumbers.map(\.e164), ["+33611223344"])
        XCTAssertEqual(items[2].clientName, "Entreprise Bêta")

        let recorded = await transport.recorded
        let activitiesRequest = try XCTUnwrap(recorded.first { $0.url?.path == "/api/v2/activities" })
        XCTAssertEqual(query(activitiesRequest, "owner_id"), "7")
        XCTAssertEqual(query(activitiesRequest, "done"), "false")
        XCTAssertEqual(activitiesRequest.value(forHTTPHeaderField: "x-api-token"), "jeton-factice")
        XCTAssertFalse(activitiesRequest.url?.absoluteString.contains("jeton-factice") ?? true)
        let dealsRequest = try XCTUnwrap(recorded.first { $0.url?.path == "/api/v2/deals" })
        XCTAssertEqual(query(dealsRequest, "ids"), "100,101")
        XCTAssertEqual(query(dealsRequest, "custom_fields"), Fixtures.scoreKey)
    }

    func testFeedWithoutScoreFieldStillWorks() async throws {
        let transport = MockTransport([
            "GET /api/v2/activities": .init(status: 200, body: Fixtures.activities),
            "GET /api/v2/dealFields": .init(status: 500, body: "{}"),
            "GET /api/v2/deals": .init(status: 200, body: Fixtures.deals),
            "GET /api/v2/persons": .init(status: 200, body: Fixtures.persons),
            "GET /api/v2/organizations": .init(status: 200, body: Fixtures.organizations),
        ])
        let loader = ActivityFeedLoader(client: PipedriveClient(configuration: config, transport: transport))
        let items = try await loader.load(ownerIDs: [7], filter: ActivityDateFilter(from: nil, to: "2026-11-07"), timeZone: paris,
                                          now: Self.seventhNoon)
        XCTAssertEqual(items.map(\.id), [1, 3, 2], "sans score : tri par date")
    }

    /// 07/11/2026 en début d'après-midi à Paris.
    static let seventhNoon = Date(timeIntervalSince1970: 1_794_052_800) // 13:00 à Paris

    func testUpcomingActivitiesComeAfterOverdueAndToday() async throws {
        let loader = ActivityFeedLoader(client: PipedriveClient(configuration: config, transport: feedTransport()))
        let items = try await loader.load(ownerIDs: [7], filter: DatePreset.defaultPreset.filter(timeZone: paris),
                                          timeZone: paris, now: Self.seventhNoon)
        XCTAssertEqual(items.map(\.id), [2, 1, 3, 4],
                       "en retard et du jour par score (sans score à la fin), puis l'activité à venir malgré son score")
        XCTAssertFalse(items[2].isUpcoming(today: "2026-11-07", timeZone: paris))
        XCTAssertTrue(items[3].isUpcoming(today: "2026-11-07", timeZone: paris))
    }

    func testFeedForSeveralUsersMergesWithoutDuplicates() async throws {
        let transport = feedTransport()
        let loader = ActivityFeedLoader(client: PipedriveClient(configuration: config, transport: transport))
        // Le faux transport renvoie les mêmes activités pour chaque utilisateur : pas de doublon attendu.
        let items = try await loader.load(ownerIDs: [7, 8, 7], filter: ActivityDateFilter(from: nil, to: nil), timeZone: paris)
        XCTAssertEqual(items.count, 4)
        let recorded = await transport.recorded
        let owners = Set(recorded.filter { $0.url?.path == "/api/v2/activities" }.compactMap { query($0, "owner_id") })
        XCTAssertEqual(owners, ["7", "8"])
    }

    func testUsers() async throws {
        let transport = MockTransport(["GET /api/v1/users": .init(status: 200, body: #"{"success":true,"data":[{"id":7,"name":"Moi","email":"moi@example.com","active_flag":true},{"id":8,"name":"Ancien","active_flag":false}]}"#)])
        let users = try await PipedriveClient(configuration: config, transport: transport).users()
        XCTAssertEqual(users.map(\.name), ["Moi", "Ancien"])
        XCTAssertEqual(users.map(\.isActive), [true, false])
    }

    func testDoneActivityBodyUsesUTC() throws {
        let type = ActivityType(id: 2, name: "Répondeur ON/OFF", key: "rpondeur_onoff", isActive: true)
        // 07/11/2026 à 13:32 à Paris = 12:32 UTC
        let date = try XCTUnwrap(FrenchFormat.parseInstant("2026-11-07T12:32:10Z"))
        let body = PipedriveClient.doneActivityBody(type: type, subject: type.name, date: date, ownerID: 7,
                                                    dealID: 100, orgID: 300, personID: 200)
        XCTAssertEqual(body["type"], .string("rpondeur_onoff"))
        XCTAssertEqual(body["subject"], .string("Répondeur ON/OFF"))
        XCTAssertEqual(body["done"], .bool(true))
        XCTAssertEqual(body["due_date"], .string("2026-11-07"))
        XCTAssertEqual(body["due_time"], .string("12:32"))
        XCTAssertEqual(body["participants"], .array([.object(["person_id": .int(200), "primary": .bool(true)])]))
        XCTAssertNil(PipedriveClient.doneActivityBody(type: type, subject: "x", date: date, ownerID: nil,
                                                      dealID: nil, orgID: nil, personID: nil)["participants"])
    }

    func testCreateAndDeleteActivity() async throws {
        let transport = MockTransport([
            "POST /api/v2/activities": .init(status: 201, body: #"{"success":true,"data":{"id":555}}"#),
            "DELETE /api/v2/activities/555": .init(status: 200, body: #"{"success":true,"data":{"id":555}}"#),
        ])
        let client = PipedriveClient(configuration: config, transport: transport)
        let type = ActivityType(id: 3, name: "Répondeur sans message", key: "rpondeur_sans_message", isActive: true)
        let id = try await client.createDoneActivity(type: type, subject: type.name, date: Date(), ownerID: 7,
                                                     dealID: 100, orgID: nil, personID: nil)
        XCTAssertEqual(id, 555)
        try await client.deleteActivity(id: id)
        let recorded = await transport.recorded
        XCTAssertEqual(recorded.map { $0.httpMethod ?? "" }, ["POST", "DELETE"])
        let sent = try decode(String(decoding: try XCTUnwrap(recorded[0].httpBody), as: UTF8.self))
        XCTAssertEqual(sent["type"], .string("rpondeur_sans_message"))
        XCTAssertEqual(sent["deal_id"], .int(100))
        XCTAssertEqual(sent["note"], .null, "pas de note par défaut")
    }

    func testDebriefCallCarriesTemplateNote() async throws {
        let transport = MockTransport(["POST /api/v2/activities": .init(status: 201, body: #"{"success":true,"data":{"id":556}}"#)])
        let client = PipedriveClient(configuration: config, transport: transport)
        let type = ActivityType(id: 4, name: DebriefTemplate.typeName, key: "call_effectue", isActive: true)
        _ = try await client.createDoneActivity(type: type, subject: type.name, date: Date(), ownerID: 7,
                                                dealID: 100, orgID: nil, personID: 200, note: DebriefTemplate.noteHTML)
        let recorded = await transport.recorded
        let sent = try decode(String(decoding: try XCTUnwrap(recorded.first?.httpBody), as: UTF8.self))
        XCTAssertEqual(sent["type"], .string("call_effectue"))
        XCTAssertEqual(sent["subject"], .string("Call effectué"))
        XCTAssertEqual(sent["note"], .string("<b>Je l'ai eu au téléphone et :</b><ul><li>x</li></ul>"))
        XCTAssertEqual(PlainText.from(html: DebriefTemplate.noteHTML), "Je l'ai eu au téléphone et :\n• x")
    }

    /// Compte rendu écrit dans l'app (demande d'Yves du 10/11/2026) : texte → note HTML de « Call effectué ».
    func testDebriefTextBecomesNoteHTML() {
        XCTAssertFalse(DebriefTemplate.hasContent(DebriefTemplate.starter), "modèle seul : rien à enregistrer")
        XCTAssertFalse(DebriefTemplate.hasContent("Je l'ai eu au téléphone et :\n• \n•"))
        XCTAssertTrue(DebriefTemplate.hasContent(DebriefTemplate.starter + "OK pour un devis"))
        let text = "Je l'ai eu au téléphone et :\n• OK pour un devis SEO & SEA\n• budget < 2 000 €\n• \n\nRappeler lundi"
        XCTAssertEqual(DebriefTemplate.html(from: text),
                       "Je l'ai eu au téléphone et :<ul><li>OK pour un devis SEO &amp; SEA</li>"
                       + "<li>budget &lt; 2 000 €</li></ul><div>Rappeler lundi</div>")
        XCTAssertEqual(DebriefTemplate.html(from: "- a\n* b"), "<ul><li>a</li><li>b</li></ul>")
    }

    /// « Autres contacts » de la fenêtre des numéros (demande d'Yves du 13/11/2026) : la société, sans la personne
    /// déjà affichée, par ordre alphabétique (accents et majuscules ignorés).
    func testOtherContactsOfTheOrganization() async throws {
        let transport = MockTransport(["GET /api/v2/persons": .init(status: 200, body: #"""
        {"success":true,"data":[
          {"id":201,"name":"Élodie Test","org_id":300,"phones":[{"label":"mobile","value":"06 11 22 33 44","primary":true}],"emails":[]},
          {"id":200,"name":"Camille Test","org_id":300,"phones":[],"emails":[]},
          {"id":202,"name":"alain Test","org_id":300,"phones":[],"emails":[{"label":"work","value":"alain@example.com","primary":true}]}
        ]}
        """#)])
        let people = try await PipedriveClient(configuration: config, transport: transport)
            .persons(organizationID: 300, excluding: 200)
        XCTAssertEqual(people.map(\.name), ["alain Test", "Élodie Test"])
        XCTAssertEqual(people.last?.callableNumbers.first?.e164, "+33611223344")
        XCTAssertEqual(people.last?.callableNumbers.first?.label, "Mobile")
        XCTAssertEqual(people.first?.emails.first?.value, "alain@example.com")
        let recorded = await transport.recorded
        let request = try XCTUnwrap(recorded.first)
        let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "org_id", value: "300")))
    }

    func testLastMailUsesFirstMessageOfThreadForGmailID() async throws {
        let transport = MockTransport([
            "GET /api/v1/persons/200/mailMessages": .init(status: 200, body: Fixtures.personMails),
            "GET /api/v1/mailbox/mailThreads/55/mailMessages": .init(status: 200, body: Fixtures.threadMails),
        ])
        let hint = try await PipedriveClient(configuration: config, transport: transport)
            .lastMail(personID: 200, clientEmails: ["client@example.com"], myEmail: "moi@example.com")
        XCTAssertEqual(hint?.subject, "Re: Votre projet", "mail du collègue et mail à quelqu'un d'autre ignorés")
        XCTAssertEqual(hint?.gmailMessageID, "1e00000000000def")
    }

    func testLastMailSentByMeToClient() throws {
        func message(from: String, to: String, cc: String = "") throws -> JSONValue {
            let ccPart = cc.isEmpty ? "" : #"{"email_address":"\#(cc)"}"#
            return try decode(#"{"data":{"id":1,"from":[{"email_address":"\#(from)"}],"to":[{"email_address":"\#(to)"}],"cc":[\#(ccPart)]}}"#)
        }
        let clients = ["client@example.com"]
        XCTAssertTrue(PipedriveClient.isBetweenMeAndClient(try message(from: "moi@example.com", to: "client@example.com"),
                                                           clientEmails: clients, myEmail: "moi@example.com"))
        XCTAssertTrue(PipedriveClient.isBetweenMeAndClient(try message(from: "moi@example.com", to: "x@example.com", cc: "client@example.com"),
                                                           clientEmails: clients, myEmail: "moi@example.com"))
        XCTAssertTrue(PipedriveClient.isBetweenMeAndClient(try message(from: "client@example.com", to: "x@example.com"),
                                                           clientEmails: clients, myEmail: "moi@example.com"))
        XCTAssertFalse(PipedriveClient.isBetweenMeAndClient(try message(from: "collegue@example.com", to: "client@example.com"),
                                                            clientEmails: clients, myEmail: "moi@example.com"))
    }

    func testLastMailWithoutMessages() async throws {
        let transport = MockTransport(["GET /api/v1/persons/200/mailMessages": .init(status: 200, body: #"{"success":true,"data":null}"#)])
        let hint = try await PipedriveClient(configuration: config, transport: transport)
            .lastMail(personID: 200, clientEmails: ["client@example.com"], myEmail: "moi@example.com")
        XCTAssertNil(hint)
    }

    func testCurrentUserAndErrors() async throws {
        let transport = MockTransport([
            "GET /api/v1/users/me": .init(status: 200, body: Fixtures.me),
            "GET /api/v1/activityTypes": .init(status: 401, body: #"{"success":false,"error":"unauthorized"}"#),
        ])
        let client = PipedriveClient(configuration: config, transport: transport)
        let me = try await client.currentUser()
        XCTAssertEqual(me.id, 7)
        XCTAssertEqual(me.email, "moi@example.com")
        do {
            _ = try await client.activityTypes()
            XCTFail("erreur attendue")
        } catch let error as PipedriveError {
            XCTAssertEqual(error, .unauthorized)
        }
        let noToken = PipedriveClient(configuration: .init(companyDomain: "test", apiToken: " "), transport: transport)
        do {
            _ = try await noToken.currentUser()
            XCTFail("erreur attendue")
        } catch let error as PipedriveError {
            XCTAssertEqual(error, .missingToken)
        }
    }
}
