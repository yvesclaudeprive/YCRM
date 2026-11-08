import XCTest
@testable import PipedriveKit

/// Étiquettes « Devis envoyé » et « 1er call à faire » (données fictives).
final class LeadTagsTests: XCTestCase {
    let names = [
        "call_effectue": "Call effectué",
        "devis_envoy": "Devis envoyé",
        "rpondeur_sans_message": "Répondeur sans message",
        "aircall_outbound_answered_": "Aircall outbound answered call",
        "aircall_outbound_unanswere": "Aircall outbound unanswered call",
        "aircall_missed_call_withou": "Aircall missed call without voicemail",
        "task": "Tâche",
    ]

    func done(_ type: String, _ subject: String = "", day: String = "2026-11-03") -> Activity {
        Activity(id: 1, subject: subject, type: type, dueDate: day, dueTime: nil, dealID: 100, personID: 200, orgID: nil,
                 done: true)
    }

    func testConversationRules() {
        XCTAssertTrue(LeadTagRules.isConversation(done("call_effectue", "Call effectué"), typeNames: names))
        XCTAssertTrue(LeadTagRules.isConversation(done("aircall_outbound_answered_"), typeNames: names))
        XCTAssertTrue(LeadTagRules.isConversation(done("aircall_inbound_answered_c"), typeNames: [:]))
        XCTAssertTrue(LeadTagRules.isConversation(done("meeting"), typeNames: [:]))
        XCTAssertTrue(LeadTagRules.isConversation(done("google_agenda"), typeNames: [:]))
        XCTAssertFalse(LeadTagRules.isConversation(done("aircall_outbound_unanswere"), typeNames: names))
        XCTAssertFalse(LeadTagRules.isConversation(done("aircall_missed_call_withou"), typeNames: names))
        XCTAssertFalse(LeadTagRules.isConversation(done("rpondeur_sans_message"), typeNames: names))
        XCTAssertFalse(LeadTagRules.isConversation(done("repondeur_onoff"), typeNames: [:]))
        XCTAssertFalse(LeadTagRules.isConversation(done("sms_envoy"), typeNames: [:]))
        XCTAssertFalse(LeadTagRules.isConversation(done("task", "Relancer"), typeNames: names))
        let planned = Activity(id: 2, subject: "", type: "call_effectue", dueDate: nil, dueTime: nil, dealID: nil,
                               personID: nil, orgID: nil, done: false)
        XCTAssertFalse(LeadTagRules.isConversation(planned, typeNames: names), "seules les activités faites comptent")
    }

    func testQuoteRules() {
        XCTAssertTrue(LeadTagRules.isQuoteSent(done("devis_envoy", "Devis SEO envoyé"), typeNames: names))
        XCTAssertTrue(LeadTagRules.isQuoteSent(done("task", "DEVIS refonte renvoyé"), typeNames: names))
        XCTAssertTrue(LeadTagRules.isQuoteSent(done("task", "Envoyer le devis audit sécu"), typeNames: names))
        XCTAssertFalse(LeadTagRules.isQuoteSent(done("task", "Préparer le devis"), typeNames: names))
        XCTAssertFalse(LeadTagRules.isQuoteSent(done("call_effectue", "Call effectué"), typeNames: names))
    }

    func testQuoteLabel() {
        let now = Date(timeIntervalSince1970: 1_794_135_600) // 08/11/2026 à 12:00
        XCTAssertEqual(LeadTags(quoteSentDay: "2026-11-03", firstCallToDo: false).quoteSentLabel(now: now, timeZone: paris),
                       "Devis envoyé · il y a 5 j")
        XCTAssertEqual(LeadTags(quoteSentDay: "2026-11-07", firstCallToDo: false).quoteSentLabel(now: now, timeZone: paris),
                       "Devis envoyé · hier")
        XCTAssertEqual(LeadTags(quoteSentDay: "2026-11-08", firstCallToDo: false).quoteSentLabel(now: now, timeZone: paris),
                       "Devis envoyé · aujourd'hui")
        XCTAssertNil(LeadTags.none.quoteSentLabel(now: now, timeZone: paris))
    }

    func client(_ transport: MockTransport) -> PipedriveClient {
        PipedriveClient(configuration: .init(companyDomain: "test", apiToken: "t"), transport: transport)
    }

    func item(deal: DealSummary? = nil) -> ActivityItem {
        let activity = Activity(id: 9, subject: "Relancer", type: "task", dueDate: "2026-11-08", dueTime: nil,
                                dealID: 100, personID: 200, orgID: nil, done: false)
        return ActivityItem(activity: activity, organizationName: "Entreprise Alpha", person: nil, deal: deal)
    }

    static let dealDone = """
    {"success":true,"data":[
      {"id":11,"subject":"Devis SEO envoyé","type":"devis_envoy","due_date":"2026-11-03","done":true,"deal_id":100,"person_id":200,"note":"<p>Envoyé par mail, <b>relance</b> lundi</p>"},
      {"id":12,"subject":"Devis SEO mis à jour renvoyé","type":"devis_envoy","due_date":"2026-11-05","done":true,"deal_id":100,"person_id":200},
      {"id":13,"subject":"Répondeur sans message","type":"rpondeur_sans_message","due_date":"2026-11-02","done":true,"deal_id":100,"person_id":200}
    ]}
    """

    func testQuoteSentAndNeverSpoken() async throws {
        let transport = MockTransport([
            "GET /api/v2/activities?deal_id=100": .init(status: 200, body: Self.dealDone),
            "GET /api/v2/activities?person_id=200": .init(status: 200, body: """
            {"success":true,"data":[{"id":14,"subject":"Missed call","type":"aircall_missed_call_withou","due_date":"2026-11-01","done":true,"person_id":200}]}
            """),
            "GET /api/v1/notes": .init(status: 200, body: #"{"success":true,"data":[{"id":1,"content":"<p>Note simple</p>"}]}"#),
        ])
        let now = Date(timeIntervalSince1970: 1_794_135_600) // 08/11/2026 à 12:00
        let tags = try await LeadTagsLoader(client: client(transport)).load(for: item(), typeNames: names, timeZone: paris,
                                                                            now: now)
        XCTAssertEqual(tags.quoteSentDay, "2026-11-05", "le plus récent")
        XCTAssertTrue(tags.firstCallToDo, "répondeur et appel manqué ne sont pas des échanges")
        XCTAssertEqual(tags.quotes.map(\.subject), ["Devis SEO mis à jour renvoyé", "Devis SEO envoyé"], "détail : le plus récent d'abord")
        XCTAssertEqual(tags.quotes.first?.dateText, "5 novembre")
        XCTAssertEqual(tags.quotes.first?.agoText(now: now, timeZone: paris), "il y a 3 j")
        XCTAssertEqual(tags.quoteSentLabel(now: now, timeZone: paris), "Devis envoyé · il y a 3 j")

        let recorded = await transport.recorded
        let first = try XCTUnwrap(recorded.first)
        XCTAssertEqual(query(first, "deal_id"), "100")
        XCTAssertEqual(query(first, "done"), "true")
        XCTAssertEqual(recorded.count, 4, "affaire, personne, puis notes Leexi de l'affaire et de la personne")
    }

    func testQuoteNoteIsPlainText() async throws {
        let transport = MockTransport([
            "GET /api/v2/activities?deal_id=100": .init(status: 200, body: Self.dealDone),
            "GET /api/v2/activities?person_id=200": .init(status: 200, body: #"{"success":true,"data":[]}"#),
            "GET /api/v1/notes": .init(status: 200, body: #"{"success":true,"data":[]}"#),
        ])
        let tags = try await LeadTagsLoader(client: client(transport)).load(for: item(), typeNames: names, timeZone: paris)
        XCTAssertEqual(tags.quotes.last?.note, "Envoyé par mail, relance lundi")
        XCTAssertNil(tags.quotes.first?.note)
    }

    func testAnsweredAircallCallOnPersonMeansSpoken() async throws {
        let transport = MockTransport([
            "GET /api/v2/activities?deal_id=100": .init(status: 200, body: Self.dealDone),
            "GET /api/v2/activities?person_id=200": .init(status: 200, body: """
            {"success":true,"data":[{"id":15,"subject":"Outbound answered call","type":"aircall_outbound_answered_","due_date":"2026-10-20","done":true,"person_id":200}]}
            """),
            "GET /api/v1/notes": .init(status: 200, body: #"{"success":true,"data":[]}"#),
        ])
        let tags = try await LeadTagsLoader(client: client(transport)).load(for: item(), typeNames: names, timeZone: paris)
        XCTAssertFalse(tags.firstCallToDo)
        XCTAssertEqual(tags.quoteSentDay, "2026-11-05")
        XCTAssertFalse(tags.isSigned)
        let count = await transport.recorded.count
        XCTAssertEqual(count, 3, "pas de notes Leexi à lire pour l'appel, mais les notes de l'affaire pour la signature")
    }

    func testSignedExcerpt() {
        XCTAssertEqual(LeadTagRules.signedExcerpt(in: "Bonjour\nc'est signé pour SEO / SEA / TMA\nmerci"), "c'est signé pour SEO / SEA / TMA")
        XCTAssertEqual(LeadTagRules.signedExcerpt(in: "CONTRAT SIGNÉ !"), "CONTRAT SIGNÉ !")
        XCTAssertNotNil(LeadTagRules.signedExcerpt(in: "Les devis sont signés depuis hier"))
        XCTAssertNil(LeadTagRules.signedExcerpt(in: "il est ok pour signer tout sur la base actuelle"))
        XCTAssertNil(LeadTagRules.signedExcerpt(in: "dit qu'il va tout signer, relancer pour signer"))
        XCTAssertNil(LeadTagRules.signedExcerpt(in: "toujours pas encore signé"))
        XCTAssertNil(LeadTagRules.signedExcerpt(in: "devis non signé"))
        XCTAssertNil(LeadTagRules.signedExcerpt(in: "il n'a jamais signé"))
        XCTAssertNil(LeadTagRules.signedExcerpt(in: "envoyer la signature électronique"))
    }

    static let quoteThenSignedNote = """
    {"success":true,"data":[
      {"id":21,"content":"<p>c'est signé pour SEO / SEA / TMA</p>","add_time":"2026-09-02 08:30:00"},
      {"id":22,"content":"<p>Votre réunion Leexi : il a signé avec une autre agence</p><p>Utilisateurs Leexi: Test</p>","add_time":"2026-09-20 08:30:00"}
    ]}
    """

    func signedTransport(dealActivities: String) -> MockTransport {
        MockTransport([
            "GET /api/v2/activities?deal_id=100": .init(status: 200, body: dealActivities),
            "GET /api/v2/activities?person_id=200": .init(status: 200, body: #"{"success":true,"data":[]}"#),
            "GET /api/v1/notes?deal_id=100": .init(status: 200, body: Self.quoteThenSignedNote),
            "GET /api/v1/notes": .init(status: 200, body: #"{"success":true,"data":[]}"#),
        ])
    }

    func testNoteSaysSignedAfterLastQuote() async throws {
        let activities = """
        {"success":true,"data":[
          {"id":31,"subject":"Maj devis envoyée","type":"devis_envoy","due_date":"2026-08-31","done":true,"deal_id":100,"person_id":200},
          {"id":32,"subject":"Call effectué","type":"call_effectue","due_date":"2026-09-01","done":true,"deal_id":100,"person_id":200,"note":"<ul><li>il est ok pour signer</li></ul>"}
        ]}
        """
        let now = Date(timeIntervalSince1970: 1_794_135_600) // 08/11/2026
        let tags = try await LeadTagsLoader(client: client(signedTransport(dealActivities: activities)))
            .load(for: item(), typeNames: names, timeZone: paris, now: now)
        XCTAssertTrue(tags.isSigned)
        XCTAssertEqual(tags.signature?.source, .note, "la note Leexi « a signé avec une autre agence » est ignorée")
        XCTAssertEqual(tags.signature?.day, "2026-09-02")
        XCTAssertEqual(tags.signature?.text, "c'est signé pour SEO / SEA / TMA")
        XCTAssertEqual(tags.quoteSentLabel(now: now, timeZone: paris), "Devis signé · il y a 67 j")
    }

    func testNewerQuoteAfterSignatureIsPending() async throws {
        let activities = """
        {"success":true,"data":[
          {"id":33,"subject":"Devis montée de version envoyé","type":"devis_envoy","due_date":"2026-11-03","done":true,"deal_id":100,"person_id":200},
          {"id":31,"subject":"Maj devis envoyée","type":"devis_envoy","due_date":"2026-08-31","done":true,"deal_id":100,"person_id":200}
        ]}
        """
        let now = Date(timeIntervalSince1970: 1_794_135_600)
        let tags = try await LeadTagsLoader(client: client(signedTransport(dealActivities: activities)))
            .load(for: item(), typeNames: names, timeZone: paris, now: now)
        XCTAssertNotNil(tags.signature, "la signature est connue…")
        XCTAssertFalse(tags.isSigned, "…mais un devis plus récent attend")
        XCTAssertEqual(tags.quoteSentLabel(now: now, timeZone: paris), "Devis envoyé · il y a 5 j")
    }

    func testSignedFieldFromDeal() async throws {
        let transport = MockTransport([
            "GET /api/v2/activities": .init(status: 200, body: #"{"success":true,"data":[]}"#),
            "GET /api/v1/notes": .init(status: 200, body: #"{"success":true,"data":[]}"#),
        ])
        let deal = DealSummary(id: 100, title: "Site", orgID: nil, personID: 200, score: nil, status: "open",
                               signedDate: "2026-09-07")
        let tags = try await LeadTagsLoader(client: client(transport)).load(for: item(deal: deal), typeNames: names, timeZone: paris)
        XCTAssertTrue(tags.isSigned)
        XCTAssertEqual(tags.signature?.source, .signedField)
        XCTAssertEqual(tags.signature?.text, "Contrat signé le 07/09/2026")
    }

    func testLeexiRecordingMeansSpoken() async throws {
        let transport = MockTransport([
            "GET /api/v2/activities": .init(status: 200, body: #"{"success":true,"data":[]}"#),
            "GET /api/v1/notes": .init(status: 200, body: """
            {"success":true,"data":[{"id":2,"content":"<a href=\\"https://app.leexi.ai/fr/calls/abc\\">Appel découverte</a>"}]}
            """),
        ])
        let tags = try await LeadTagsLoader(client: client(transport)).load(for: item(), typeNames: names, timeZone: paris)
        XCTAssertFalse(tags.firstCallToDo)
        XCTAssertNil(tags.quoteSentDay)
    }

    func testWonDealIsSignedAndLostDealHasNoTags() async throws {
        let transport = MockTransport([:])
        let won = DealSummary(id: 100, title: "Site", orgID: nil, personID: 200, score: nil, status: "won",
                              wonTime: "2026-09-07T10:00:00Z")
        let now = Date(timeIntervalSince1970: 1_794_135_600)
        let tags = try await LeadTagsLoader(client: client(transport)).load(for: item(deal: won), typeNames: names,
                                                                            timeZone: paris, now: now)
        XCTAssertTrue(tags.isSigned)
        XCTAssertEqual(tags.signature?.source, .dealWon)
        XCTAssertFalse(tags.firstCallToDo)
        XCTAssertEqual(tags.quoteSentLabel(now: now, timeZone: paris), "Devis signé · il y a 62 j")

        let lost = DealSummary(id: 100, title: "Site", orgID: nil, personID: 200, score: nil, status: "lost")
        let none = try await LeadTagsLoader(client: client(transport)).load(for: item(deal: lost), typeNames: names, timeZone: paris)
        XCTAssertEqual(none, .none)
        let count = await transport.recorded.count
        XCTAssertEqual(count, 0, "affaire close : aucune requête")
    }
}
