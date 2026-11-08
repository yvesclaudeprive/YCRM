import XCTest
@testable import PipedriveKit

final class HistoryTests: XCTestCase {
    func testPlainTextFromHTML() {
        XCTAssertEqual(PlainText.from(html: "<p>Bonjour&nbsp;<b>Alice</b></p><p>Suite &amp; fin</p>"), "Bonjour Alice\nSuite & fin")
        XCTAssertEqual(PlainText.from(html: "<ul><li>un</li><li>deux</li></ul>"), "• un\n• deux")
        XCTAssertEqual(PlainText.from(html: "L&#39;app &#x2014; ok<br/>ligne 2<br><br><br>ligne 3"), "L'app — ok\nligne 2\n\nligne 3")
        XCTAssertEqual(PlainText.from(html: "&inconnu; reste"), "&inconnu; reste")
        XCTAssertEqual(PlainText.from(html: "   "), "")
    }

    func testPlainTextKeepsNestedListsAndLineBreaks() {
        let html = "<b>J'ai fait un call :</b><ul><li><b>Besoin :</b></li><ul><li>refonte</li><li>SEO</li></ul><li>Budget</li></ul>Fin<br>Suite"
        let em = "\u{2003}\u{2003}"
        XCTAssertEqual(PlainText.from(html: html),
                       "J'ai fait un call :\n• Besoin :\n\(em)◦ refonte\n\(em)◦ SEO\n• Budget\nFin\nSuite")
        XCTAssertEqual(PlainText.from(html: "<ol><li>un</li><li>deux</li></ol>"), "1. un\n2. deux")
        XCTAssertEqual(PlainText.from(html: "<div>Ligne 1</div><div>Ligne 2</div>"), "Ligne 1\nLigne 2")
    }

    func testAircallLogs() {
        XCTAssertTrue(AircallLog.isAutomaticCall(type: "aircall_outbound_answered_", text: ""))
        XCTAssertTrue(AircallLog.isAutomaticCall(type: "aircall_missed_call_with_v", text: ""))
        XCTAssertFalse(AircallLog.isAutomaticCall(type: "aircall_outbound_sms", text: ""), "un SMS a un vrai contenu")
        XCTAssertFalse(AircallLog.isAutomaticCall(type: "call_effectue", text: ""))
        XCTAssertEqual(AircallLog.frenchTitle(type: "aircall_outbound_answered_", fallback: "x"), "Appel sortant décroché")
        XCTAssertEqual(AircallLog.frenchTitle(type: "aircall_missed_call_withou", fallback: "x"), "Appel manqué")
        XCTAssertEqual(AircallLog.duration(in: "Durée : 00:02:15"), "2 min 15 s")
        XCTAssertEqual(AircallLog.duration(in: "00:00:14"), "14 s")
        XCTAssertEqual(AircallLog.duration(in: "01:05:00"), "1 h 05")
        XCTAssertNil(AircallLog.duration(in: "sans durée"))
    }

    func testAircallMessages() {
        // Libellés réels d'Aircall (« send », pas « sent »), texte sur deux lignes.
        let outbound = "Outbound SMS on Ligne Test\nSMS send to: +33 6 00 00 00 01\nAircall number: Ligne Test (+33 7 00 00 00 02)\nSend by: Utilisateur Test\n\nSMS sent: Bonjour, je vous rappelle\ndemain\n\nActivity assigned to Utilisateur Test"
        XCTAssertEqual(AircallLog.message(type: "aircall_outbound_sms", text: outbound),
                       AircallLog.Message(isOutbound: true, from: "Utilisateur Test", to: "+33 6 00 00 00 01",
                                          body: "Bonjour, je vous rappelle\ndemain"))
        let inbound = "Inbound SMS on Ligne Test\nAircall number: Ligne Test (+33 7 00 00 00 02)\nSMS send by: +33 6 00 00 00 01\n\nSMS received: OK pour moi : merci\n\nActivity assigned to Utilisateur Test"
        XCTAssertEqual(AircallLog.message(type: "aircall_inbound_sms", text: inbound),
                       AircallLog.Message(isOutbound: false, from: "+33 6 00 00 00 01", to: "Ligne Test",
                                          body: "OK pour moi : merci"))
        XCTAssertTrue(AircallLog.isMessage(type: "aircall_outbound_whatsapp_message"))
        XCTAssertFalse(AircallLog.isMessage(type: "aircall_outbound_answered_"))
        XCTAssertNil(AircallLog.message(type: "aircall_outbound_sms", text: "pas de texte"))
        let contact = PersonContact(id: 1, name: "Client Test", phones: [ContactPoint(value: "06 00 00 00 01", label: "mobile", primary: true)],
                                    emails: [], orgID: nil)
        XCTAssertEqual(AircallLog.displayName("+33 6 00 00 00 01", contact: contact), "Client Test")
        XCTAssertEqual(AircallLog.displayName("Utilisateur Test", contact: contact), "Utilisateur Test")
    }

    func testHistoryKinds() {
        XCTAssertEqual(HistoryKind(activityType: "call_effectue", name: "Call effectué"), .call)
        XCTAssertEqual(HistoryKind(activityType: "rpondeur_onoff", name: "Répondeur ON/OFF"), .voicemail)
        XCTAssertEqual(HistoryKind(activityType: "aircall_missed_call_with_v", name: "Aircall missed call with voicemail"), .voicemail)
        XCTAssertEqual(HistoryKind(activityType: "aircall_outbound_sms", name: "Aircall outbound SMS"), .message)
        XCTAssertEqual(HistoryKind(activityType: "mail_envoy", name: "Mail envoyé"), .mail)
        XCTAssertEqual(HistoryKind(activityType: "google_agenda", name: "Google agenda"), .meeting)
        XCTAssertEqual(HistoryKind(activityType: "task", name: "Tâche"), .task)
        XCTAssertEqual(HistoryKind(activityType: "devis_envoy", name: "Devis envoyé"), .other)
    }

    func client(_ transport: MockTransport) -> PipedriveClient {
        PipedriveClient(configuration: .init(companyDomain: "test", apiToken: "t"), transport: transport)
    }

    func testHistoryKeepsOnlyOwnerItemsAndSplitsLeexi() async throws {
        let transport = MockTransport([
            "GET /api/v1/notes": .init(status: 200, body: Fixtures.dealNotes),
            "GET /api/v2/activities": .init(status: 200, body: Fixtures.dealActivities),
        ])
        let activity = Activity(id: 1, subject: "Relancer", type: "task", dueDate: "2026-11-07", dueTime: nil,
                                dealID: 100, personID: nil, orgID: nil, done: false, ownerID: 7)
        let item = ActivityItem(activity: activity, organizationName: "Entreprise Alpha", person: nil, deal: nil)
        let now = Date(timeIntervalSince1970: 1_794_056_000) // 07/11/2026
        let bundle = try await HistoryLoader(client: client(transport)).load(
            for: item, typeNames: ["call_effectue": "Call effectué", "task": "Tâche"], ownerID: 7, ownerEmail: "moi@example.com",
            now: now)

        XCTAssertEqual(bundle.entries.map(\.id), ["activity-85", "activity-81", "note-71", "activity-83"],
                       "plus récent d'abord ; collègue, note vide et activité sans commentaire exclus ; Leexi à part")
        let aircall = bundle.entries[0]
        XCTAssertTrue(aircall.isAutomatic, "journal Aircall : affichage court")
        XCTAssertEqual(aircall.title, "Appel sortant décroché")
        XCTAssertEqual(aircall.text, "Durée 2 min 15 s")
        XCTAssertEqual(bundle.entries[1].kind, .call)
        XCTAssertFalse(bundle.entries[1].isAutomatic)
        XCTAssertEqual(bundle.entries[1].title, "Call effectué")
        XCTAssertEqual(bundle.entries[1].text, "A décroché, OK pour un devis")
        XCTAssertEqual(bundle.entries[1].dateText, "6 novembre à 15:00")
        XCTAssertEqual(bundle.entries[2].kind, .note)
        XCTAssertEqual(bundle.entries[2].author, "Utilisateur Test")
        XCTAssertEqual(bundle.entries[2].dateText, "5 novembre à 10:15")
        XCTAssertTrue(bundle.entries[2].text.hasPrefix("Client intéressé par le SEA :\n• budget"))
        XCTAssertEqual(bundle.entries[3].title, "Tâche · Envoyer la proposition")

        XCTAssertEqual(bundle.leexi.map(\.id), ["leexi-75"], "seul l'appel Leexi où figure mon adresse")
        let call = try XCTUnwrap(bundle.leexi.first)
        XCTAssertEqual(call.title, "Appel découverte Alpha (5 novembre à 11:00)")
        XCTAssertEqual(call.link?.absoluteString, "https://app.leexi.ai/fr/calls/abc-123")
        XCTAssertEqual(call.summary, "Découverte du besoin\nLe client veut refaire son site.")
        XCTAssertEqual(call.dateText, "5 novembre à 11:30")

        let recorded = await transport.recorded
        let notesRequest = try XCTUnwrap(recorded.first { $0.url?.path == "/api/v1/notes" })
        XCTAssertEqual(query(notesRequest, "deal_id"), "100")
        XCTAssertEqual(query(notesRequest, "sort"), "add_time DESC")
        let activitiesRequest = try XCTUnwrap(recorded.first { $0.url?.path == "/api/v2/activities" })
        XCTAssertEqual(query(activitiesRequest, "deal_id"), "100")
        XCTAssertEqual(query(activitiesRequest, "sort_direction"), "desc")
    }

    func testHistoryDeduplicatesNotesAcrossDealAndPerson() async throws {
        // Même réponse pour toutes les requêtes de notes : la note 71 ne doit apparaître qu'une fois.
        let transport = MockTransport([
            "GET /api/v1/notes": .init(status: 200, body: Fixtures.personNotes),
            "GET /api/v2/activities": .init(status: 200, body: #"{"success":true,"data":[]}"#),
        ])
        let activity = Activity(id: 1, subject: "", type: "task", dueDate: nil, dueTime: nil,
                                dealID: 100, personID: 200, orgID: 300, done: false)
        let item = ActivityItem(activity: activity, organizationName: nil, person: nil, deal: nil)
        let bundle = try await HistoryLoader(client: client(transport)).load(for: item, typeNames: [:], ownerID: nil, ownerEmail: nil)
        XCTAssertEqual(bundle.entries.map(\.id), ["note-71", "note-73"])
        XCTAssertTrue(bundle.leexi.isEmpty)
    }
}
