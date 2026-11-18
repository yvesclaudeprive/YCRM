import XCTest
@testable import PipedriveKit

/// « Dernière action » sous les boutons d'historique (demande d'Yves du 18/11/2026). Données fictives.
final class LastActionTests: XCTestCase {
    let names = [
        "call_effectue": "Call effectué",
        "rpondeur_sans_message": "Répondeur sans message",
        "repondeur_onoff": "Répondeur ON/OFF",
        "msg_vocal": "Msg vocal",
        "sms_envoy": "Sms envoyé",
        "msg_laiss_aux_collgues": "Msg laissé aux collègues",
        "task": "Tâche",
        "devis_envoy": "Devis envoyé",
        "email": "E-mail",
    ]
    let now = Date(timeIntervalSince1970: 1_794_135_600) // 08/11/2026 à 12:00 (Paris)

    func activity(_ id: Int, _ type: String, _ subject: String = "", day: String = "2026-11-05", time: String? = nil,
                  note: String? = nil, owner: Int? = 7, added: String? = nil, done: Bool = true) -> Activity {
        Activity(id: id, subject: subject, type: type, dueDate: day, dueTime: time, dealID: 100, personID: 200,
                 orgID: nil, done: done, note: note, ownerID: owner, addTime: added)
    }

    func label(_ activity: Activity) -> String? {
        LastAction.describe(activity, typeName: names[activity.type] ?? activity.type)?.label
    }

    func testLabels() {
        XCTAssertEqual(label(activity(1, "call_effectue", "Call effectué")), "Call effectué")
        XCTAssertEqual(label(activity(1, "rpondeur_sans_message")), "Répondeur")
        XCTAssertEqual(label(activity(1, "repondeur_onoff")), "Répondeur ON/OFF")
        XCTAssertEqual(label(activity(1, "msg_vocal")), "Msg vocal")
        XCTAssertEqual(label(activity(1, "sms_envoy", "Sms envoyé")), "SMS envoyé")
        XCTAssertEqual(label(activity(1, "sms_envoy", "WhatsApp envoyé")), "WhatsApp envoyé")
        XCTAssertEqual(label(activity(1, "msg_laiss_aux_collgues")), "Msg laissé aux collègues")
        XCTAssertEqual(label(activity(1, "repondeur_aircall", "Répondeur Aircall")), "Répondeur Aircall")
        XCTAssertEqual(label(activity(1, "aircall_outbound_answered_", note: "Duration of call: 00:00:27")),
                       "Répondeur Aircall", "décroché moins d'une minute = la messagerie")
        XCTAssertEqual(label(activity(1, "aircall_outbound_answered_", note: "Duration of call: 00:04:12")),
                       "Appel Aircall (4 min)")
        XCTAssertEqual(label(activity(1, "aircall_outbound_unanswere")), "Appel sans réponse")
        XCTAssertEqual(label(activity(1, "aircall_inbound_answered_c", note: "Waiting time: 00:00:14<br>Duration of call: 00:06:01")),
                       "Appel reçu (6 min)")
        XCTAssertEqual(label(activity(1, "aircall_outbound_sms")), "SMS envoyé (Aircall)")
        XCTAssertEqual(label(activity(1, "google_agenda", "call ALPHA / YATEO")), "RDV")
        // Pas des actions de contact : appels manqués du client, SMS reçus, tâches, devis, e-mails.
        XCTAssertNil(label(activity(1, "aircall_missed_call_withou")))
        XCTAssertNil(label(activity(1, "aircall_missed_call_with_v")))
        XCTAssertNil(label(activity(1, "aircall_inbound_sms")))
        XCTAssertNil(label(activity(1, "task", "Relancer pour le devis")))
        XCTAssertNil(label(activity(1, "devis_envoy", "Devis SEO envoyé")))
        XCTAssertNil(label(activity(1, "email", "Mail envoyé")))
        XCTAssertNil(label(activity(1, "rpondeur_sans_message", done: false)), "seules les activités faites comptent")
    }

    func testLatestIsTheMostRecentOfMine() throws {
        let activities = [
            activity(1, "call_effectue", "Call effectué", day: "2026-11-02"),
            activity(2, "rpondeur_sans_message", day: "2026-11-05", time: "15:49"),
            activity(3, "task", "Relancer", day: "2026-11-07", time: "09:00"),
            activity(4, "email", "Mail envoyé", day: "2026-11-07", time: "10:00"),
            activity(5, "call_effectue", "Call effectué", day: "2026-11-06", time: "10:00", owner: 8),
        ]
        let last = try XCTUnwrap(LastAction.latest(in: activities, typeNames: names, ownerID: 7, ownerName: nil, now: now))
        XCTAssertEqual(last.label, "Répondeur", "ni tâche, ni e-mail, ni l'action d'un autre utilisateur")
        XCTAssertEqual(last.activityID, 2)
        XCTAssertEqual(last.dateText(now: now, timeZone: paris), "5 novembre à 16:49")
        XCTAssertEqual(last.agoText(now: now, timeZone: paris), "il y a 3 j")
        XCTAssertEqual(last.summary(now: now, timeZone: paris), "Répondeur · 5 novembre à 16:49 · il y a 3 j")
        XCTAssertNil(LastAction.latest(in: [activities[2], activities[3]], typeNames: names, ownerID: 7, ownerName: nil,
                                       now: now))
    }

    /// Les journaux Aircall sont attribués au propriétaire du contact même quand un collègue appelle : seuls mes appels.
    func testAircallCallsOfColleaguesAreIgnored() throws {
        let colleague = activity(1, "aircall_outbound_answered_", day: "2026-11-07", time: "14:00",
                                 note: "Outbound answered call<br>Made by Camille TEST<br>Duration of call: 00:05:44")
        let mine = activity(2, "aircall_outbound_answered_", day: "2026-11-06", time: "14:00",
                            note: "Outbound answered call<br>Made by Utilisateur TEST<br>Duration of call: 00:00:20")
        let answered = activity(3, "aircall_inbound_answered_c", day: "2026-11-07", time: "16:00",
                                note: "Inbound answered call<br>Answered by Camille Test<br>Duration of call: 00:03:00")
        let last = try XCTUnwrap(LastAction.latest(in: [colleague, mine, answered], typeNames: names, ownerID: 7,
                                                   ownerName: "Utilisateur Test", now: now))
        XCTAssertEqual(last.activityID, 2)
        XCTAssertEqual(last.label, "Répondeur Aircall")
        // Nom inconnu : tous les appels comptent.
        let any = try XCTUnwrap(LastAction.latest(in: [colleague, mine, answered], typeNames: names, ownerID: 7,
                                                  ownerName: nil, now: now))
        XCTAssertEqual(any.activityID, 3)
        XCTAssertEqual(AircallLog.agent(in: "Outbound answered call\nMade by Utilisateur TEST\n\nActivity assigned to X"),
                       "Utilisateur TEST")
        XCTAssertEqual(AircallLog.agent(in: "Answered by Camille Test"), "Camille Test")
        XCTAssertNil(AircallLog.agent(in: "Missed call\nWaiting time: 00:00:35"))
    }

    func testMomentAndRelativeDays() throws {
        // Noté sans heure le jour même : l'heure de création.
        let debrief = activity(1, "call_effectue", "Call effectué", day: "2026-11-08", added: "2026-11-08T09:15:00Z")
        let last = try XCTUnwrap(LastAction.latest(in: [debrief], typeNames: names, ownerID: 7, ownerName: nil, now: now))
        XCTAssertEqual(last.dateText(now: now, timeZone: paris), "8 novembre à 10:15")
        XCTAssertEqual(last.agoText(now: now, timeZone: paris), "aujourd'hui")
        // Sans heure ni création : le jour seul.
        let dayOnly = activity(2, "msg_vocal", day: "2026-11-07")
        let yesterday = try XCTUnwrap(LastAction.latest(in: [dayOnly], typeNames: names, ownerID: 7, ownerName: nil,
                                                        now: now))
        XCTAssertEqual(yesterday.dateText(now: now, timeZone: paris), "7 novembre")
        XCTAssertEqual(yesterday.agoText(now: now, timeZone: paris), "hier")
        // Une activité datée dans le futur n'est pas une action passée ; doublons (affaire + contact) ignorés.
        let future = activity(3, "rpondeur_sans_message", day: "2026-11-20", time: "10:00")
        let twice = try XCTUnwrap(LastAction.latest(in: [dayOnly, future, dayOnly], typeNames: names, ownerID: 7,
                                                    ownerName: nil, now: now))
        XCTAssertEqual(twice.activityID, 2)
    }

    /// Le chargement des étiquettes trouve la dernière action dans les activités de l'affaire ET du contact.
    func testLoaderFindsLastActionOnPerson() async throws {
        let transport = MockTransport([
            "GET /api/v2/activities?deal_id=100": .init(status: 200, body: """
            {"success":true,"data":[{"id":21,"subject":"Call effectué","type":"call_effectue","due_date":"2026-11-02","done":true,"deal_id":100,"person_id":200,"owner_id":7}]}
            """),
            "GET /api/v2/activities?person_id=200": .init(status: 200, body: """
            {"success":true,"data":[{"id":22,"subject":"Outbound answered call","type":"aircall_outbound_answered_","due_date":"2026-11-06","due_time":"15:46","done":true,"person_id":200,"owner_id":7,"note":"Made by Utilisateur Test<br>Duration of call: 00:00:27"}]}
            """),
            "GET /api/v1/notes": .init(status: 200, body: #"{"success":true,"data":[]}"#),
        ])
        let activity = Activity(id: 9, subject: "Relancer", type: "task", dueDate: "2026-11-08", dueTime: nil,
                                dealID: 100, personID: 200, orgID: nil, done: false, ownerID: 7)
        let item = ActivityItem(activity: activity, organizationName: "Entreprise Alpha", person: nil, deal: nil)
        let client = PipedriveClient(configuration: .init(companyDomain: "test", apiToken: "t"), transport: transport)
        let tags = try await LeadTagsLoader(client: client).load(for: item, typeNames: names, timeZone: paris, now: now,
                                                                ownerName: "Utilisateur Test")
        XCTAssertTrue(tags.lastActionChecked)
        XCTAssertEqual(tags.lastAction?.label, "Répondeur Aircall")
        XCTAssertEqual(tags.lastAction?.summary(now: now, timeZone: paris), "Répondeur Aircall · 6 novembre à 16:46 · il y a 2 j")
        XCTAssertFalse(tags.firstCallToDo, "le « Call effectué » de l'affaire reste un échange")
        let paths = await transport.recorded.compactMap { $0.url?.path }
        XCTAssertEqual(paths.filter { $0 == "/api/v2/activities" }.count, 2, "affaire et contact, une seule fois chacun")
        // Les étiquettes recalculées gardent la dernière action.
        let more = tags.adding(meetings: [UpcomingMeeting(title: "call", day: "2026-11-10", time: "10:00", source: .pipedrive)],
                               now: now, timeZone: paris)
        XCTAssertEqual(more.lastAction, tags.lastAction)
        XCTAssertTrue(more.lastActionChecked)
    }
}
