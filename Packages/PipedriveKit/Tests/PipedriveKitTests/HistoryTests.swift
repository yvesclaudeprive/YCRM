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

    /// Appels sans réponse, messages vocaux et SMS notés sans commentaire : visibles (demande d'Yves du 09/11/2026).
    func testHistoryShowsAttemptsWithoutComment() async throws {
        let dealActivities = """
        {"success":true,"data":[
          {"id":91,"subject":"Outbound unanswered call on Ligne Test","type":"aircall_outbound_unanswere","due_date":"2026-11-06","due_time":"09:00","deal_id":100,"person_id":200,"done":true,"owner_id":7,"note":"Outbound unanswered call on Ligne Test<br>Waiting time: 00:00:08<br>Made by Utilisateur Test"},
          {"id":92,"subject":"Msg vocal","type":"msg_vocal","due_date":"2026-11-06","due_time":"09:01","deal_id":100,"person_id":200,"done":true,"owner_id":7,"note":null},
          {"id":93,"subject":"WhatsApp envoyé","type":"sms_envoy","due_date":"2026-11-05","due_time":"10:00","deal_id":100,"person_id":200,"done":true,"owner_id":7,"note":""},
          {"id":94,"subject":"Rappeler","type":"task","due_date":"2026-11-04","due_time":null,"deal_id":100,"person_id":200,"done":true,"owner_id":7,"note":""},
          {"id":95,"subject":"Msg vocal","type":"msg_vocal","due_date":"2026-11-20","due_time":null,"deal_id":100,"person_id":200,"done":false,"owner_id":7,"note":null},
          {"id":96,"subject":"Inbound answered call","type":"aircall_inbound_answered_c","due_date":"2026-11-03","due_time":"08:00","deal_id":100,"person_id":200,"done":true,"owner_id":7,"note":"Inbound answered call<br>Waiting time: 00:00:11<br>Answered by Utilisateur Test<br><br>Duration of call: 00:03:10"}
        ]}
        """
        let personActivities = """
        {"success":true,"data":[
          {"id":91,"subject":"Doublon","type":"aircall_outbound_unanswere","due_date":"2026-11-06","due_time":"09:00","deal_id":100,"person_id":200,"done":true,"owner_id":7,"note":"Waiting time: 00:00:08"},
          {"id":97,"subject":"Missed call on Ligne Test","type":"aircall_missed_call_withou","due_date":"2026-11-02","due_time":"16:00","deal_id":null,"person_id":200,"done":true,"owner_id":7,"note":"Missed call on Ligne Test<br>Waiting time: 00:00:14"},
          {"id":98,"subject":"Autre affaire","type":"task","due_date":"2026-11-02","due_time":null,"deal_id":555,"person_id":200,"done":true,"owner_id":7,"note":"Sujet d'une autre affaire"}
        ]}
        """
        let transport = MockTransport([
            "GET /api/v1/notes": .init(status: 200, body: #"{"success":true,"data":[]}"#),
            "GET /api/v2/activities": .init(status: 200, body: dealActivities),
            "GET /api/v2/activities?person_id=200": .init(status: 200, body: personActivities),
        ])
        let activity = Activity(id: 1, subject: "Relancer", type: "task", dueDate: "2026-11-07", dueTime: nil,
                                dealID: 100, personID: 200, orgID: nil, done: false, ownerID: 7)
        let item = ActivityItem(activity: activity, organizationName: "Entreprise Alpha", person: nil, deal: nil)
        let now = Date(timeIntervalSince1970: 1_794_056_000) // 07/11/2026
        let bundle = try await HistoryLoader(client: client(transport)).load(
            for: item, typeNames: ["msg_vocal": "Msg vocal", "sms_envoy": "Sms envoyé", "task": "Tâche"], ownerID: 7,
            ownerEmail: "moi@example.com", now: now)
        XCTAssertEqual(bundle.entries.map(\.id), ["activity-92", "activity-91", "activity-93", "activity-96", "activity-97"],
                       "tâche sans commentaire, alerte pas encore faite et autre affaire exclues ; doublon une fois")
        let byID = Dictionary(uniqueKeysWithValues: bundle.entries.map { ($0.id, $0) })
        XCTAssertEqual(byID["activity-91"]?.title, "Appel sortant sans réponse")
        XCTAssertEqual(byID["activity-91"]?.text, "Sonnerie 8 s")
        XCTAssertEqual(byID["activity-92"]?.title, "Msg vocal")
        XCTAssertEqual(byID["activity-92"]?.kind, .voicemail)
        XCTAssertEqual(byID["activity-92"]?.isAutomatic, true)
        XCTAssertEqual(byID["activity-92"]?.badge, "Répondeur + msg vocal")
        XCTAssertEqual(byID["activity-91"]?.channel, .aircall)
        XCTAssertEqual(byID["activity-93"]?.title, "Sms envoyé · WhatsApp envoyé")
        XCTAssertEqual(byID["activity-96"]?.text, "Durée 3 min 10 s", "l'attente avant de décrocher n'est pas la durée")
        XCTAssertEqual(byID["activity-97"]?.title, "Appel manqué")
        XCTAssertEqual(byID["activity-97"]?.text, "Sonnerie 14 s")
    }

    /// Doublons nettoyés (demande d'Yves du 09/11/2026, données fictives inspirées d'un vrai historique) : 3 journaux
    /// « décroché » à la même minute = 2 répondeurs + l'appel du « Call effectué » ; répondeur Aircall reconnu.
    func testHistoryMergesAircallDuplicatesAndVoicemails() {
        func act(_ id: Int, _ type: String, _ day: String, _ time: String?, note: String? = nil, added: String? = nil,
                 subject: String = "") -> Activity {
            Activity(id: id, subject: subject, type: type, dueDate: day, dueTime: time, dealID: 100, personID: 200, orgID: nil,
                     done: true, note: note, ownerID: 7, addTime: added)
        }
        let answered = "aircall_outbound_answered_"
        let activities = [
            act(1, answered, "2026-07-02", "10:03", note: "Outbound answered call<br>Duration of call: 00:00:27"),
            act(2, answered, "2026-07-02", "10:03", note: "Outbound answered call<br>Duration of call: 00:00:18"),
            act(3, answered, "2026-07-02", "10:03", note: "Outbound answered call<br>Duration of call: 00:05:04"),
            act(4, "call_effectue", "2026-07-02", nil, note: "Je l'ai eu et : il veut un point", added: "2026-07-02T10:10:54Z",
                subject: "Call effectué"),
            act(5, answered, "2026-09-01", "15:35", note: "Outbound answered call<br>Duration of call: 00:00:26"),
            act(6, answered, "2026-09-04", "08:15", note: "Outbound answered call<br>Duration of call: 00:00:20"),
            act(7, "rpondeur_sans_message", "2026-09-04", "08:30", subject: "Répondeur sans message"),
            act(8, "repondeur_onoff", "2026-09-07", "13:30", subject: "Répondeur ON/OFF"),
            act(9, "msg_vocal", "2026-09-08", "09:00", subject: "Msg vocal"),
        ]
        let names = ["call_effectue": "Call effectué", "rpondeur_sans_message": "Répondeur sans message",
                     "repondeur_onoff": "Répondeur ON/OFF", "msg_vocal": "Msg vocal"]
        let entries = HistoryLoader.activityEntries(activities, typeNames: names, contact: nil,
                                                    now: Date(timeIntervalSince1970: 1_794_056_000))
        XCTAssertEqual(entries.count, 6, entries.map(\.title).joined(separator: " / "))
        XCTAssertEqual(Array(entries.map(\.id).prefix(5)),
                       ["activity-9", "activity-8", "activity-7", "activity-5", "activity-4"])
        XCTAssertEqual(entries[0].badge, "Répondeur + msg vocal")
        XCTAssertNil(entries[0].channel)
        XCTAssertEqual(entries[1].channel, .onoff)
        XCTAssertEqual(entries[1].badge, "Répondeur")
        XCTAssertEqual(entries[2].title, "Répondeur sans message")
        XCTAssertEqual(entries[2].channel, .aircall, "le journal Aircall de 20 s juste avant est fondu dedans")
        XCTAssertEqual(entries[3].title, "Répondeur Aircall")
        XCTAssertEqual(entries[3].kind, .voicemail)
        XCTAssertEqual(entries[3].text, "Durée 26 s")
        XCTAssertEqual(entries[3].channel, .aircall)
        XCTAssertEqual(entries[4].title, "Call effectué · 5 min 4 s", "l'appel décroché le plus long est celui du compte rendu")
        XCTAssertEqual(entries[4].channel, .aircall)
        XCTAssertEqual(entries[4].text, "Je l'ai eu et : il veut un point")
        XCTAssertEqual(entries[5].title, "Répondeur Aircall ×2")
        XCTAssertEqual(entries[5].text, "")
    }

    func testCallDurationIgnoresWaitingTime() {
        XCTAssertEqual(AircallLog.seconds(in: "Waiting time: 00:00:11<br>Duration of call: 00:03:10"), 190)
        XCTAssertNil(AircallLog.seconds(in: "Missed call<br>Waiting time: 00:00:14"))
        XCTAssertEqual(AircallLog.waitingSeconds(in: "Missed call<br>Waiting time: 00:00:14"), 14)
        XCTAssertEqual(AircallLog.summary(type: "aircall_outbound_answered_", text: "Duration of call: 00:00:21"), "Durée 21 s")
        XCTAssertTrue(AircallLog.isUnanswered(type: "aircall_missed_call_with_v"))
        XCTAssertFalse(AircallLog.isUnanswered(type: "aircall_inbound_answered_c"))
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
        XCTAssertEqual(bundle.entries[1].dateText, "vendredi 6 novembre à 15:00", "jour de la semaine dans l'historique")
        XCTAssertEqual(bundle.entries[2].kind, .note)
        XCTAssertEqual(bundle.entries[2].author, "Utilisateur Test")
        XCTAssertEqual(bundle.entries[2].dateText, "jeudi 5 novembre à 10:15")
        XCTAssertTrue(bundle.entries[2].text.hasPrefix("Client intéressé par le SEA :\n• budget"))
        XCTAssertEqual(bundle.entries[3].title, "Tâche · Envoyer la proposition")

        XCTAssertEqual(bundle.leexi.map(\.id), ["leexi-75"], "seul l'appel Leexi où figure mon adresse")
        let call = try XCTUnwrap(bundle.leexi.first)
        XCTAssertEqual(call.title, "Appel découverte Alpha (5 novembre à 11:00)")
        XCTAssertEqual(call.link?.absoluteString, "https://app.leexi.ai/fr/calls/abc-123")
        XCTAssertEqual(call.summary, "Découverte du besoin\nLe client veut refaire son site.")
        XCTAssertEqual(call.dateText, "jeudi 5 novembre à 11:30")

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
