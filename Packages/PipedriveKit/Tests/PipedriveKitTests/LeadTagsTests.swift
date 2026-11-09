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

    func done(_ type: String, _ subject: String = "", day: String = "2026-11-03", note: String? = nil) -> Activity {
        Activity(id: 1, subject: subject, type: type, dueDate: day, dueTime: nil, dealID: 100, personID: 200, orgID: nil,
                 done: true, note: note)
    }

    /// Aircall dit « décroché » quand la messagerie répond : moins d'une minute, ce n'est pas un échange.
    func testShortAnsweredCallIsVoicemail() {
        let short = done("aircall_outbound_answered_", note: "Outbound answered call<br>Duration of call: 00:00:21")
        let real = done("aircall_outbound_answered_", note: "Outbound answered call<br>Duration of call: 00:04:12")
        let minute = done("aircall_inbound_answered_c", note: "Duration of call: 00:01:00")
        XCTAssertFalse(LeadTagRules.isConversation(short, typeNames: names))
        XCTAssertTrue(LeadTagRules.isConversation(real, typeNames: names))
        XCTAssertTrue(LeadTagRules.isConversation(minute, typeNames: [:]))
        XCTAssertEqual(AircallLog.seconds(in: "Duration of call: 00:04:12"), 252)
        XCTAssertEqual(AircallLog.duration(in: "Duration of call: 01:05:00"), "1 h 05")
        XCTAssertEqual(AircallLog.duration(in: "Duration of call: 00:02:15"), "2 min 15 s")
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
        XCTAssertTrue(LeadTagRules.isQuoteSent(done("task", "devis TMA envoyé"), typeNames: names))
        XCTAssertTrue(LeadTagRules.isQuoteSent(done("task", "Devis lot 1 + lot 2 envoyés"), typeNames: names))
        // Tâche à faire, même cochée : pas la preuve d'un envoi (retour d'Yves du 08/11/2026).
        XCTAssertFalse(LeadTagRules.isQuoteSent(done("task", "Envoyer le devis audit sécu"), typeNames: names))
        XCTAssertFalse(LeadTagRules.isQuoteSent(done("task", "Client Test : envoyer les 2 devis (option A / option B)"),
                                                typeNames: names))
        XCTAssertFalse(LeadTagRules.isQuoteSent(done("task", "Envoi devis SEO"), typeNames: names))
        XCTAssertFalse(LeadTagRules.isQuoteSent(done("task", "Préparer le devis"), typeNames: names))
        XCTAssertFalse(LeadTagRules.isQuoteSent(done("call_effectue", "Call effectué"), typeNames: names))
    }

    func testQuoteLabel() {
        let now = Date(timeIntervalSince1970: 1_794_135_600) // 08/11/2026 à 12:00
        XCTAssertEqual(LeadTags(quoteSentDay: "2026-11-03", firstCallToDo: false).quoteSentLabel(now: now, timeZone: paris),
                       "Devis - Devis envoyé - 5j")
        XCTAssertEqual(LeadTags(quoteSentDay: "2026-11-07", firstCallToDo: false).quoteSentLabel(now: now, timeZone: paris),
                       "Devis - Devis envoyé - 1j")
        XCTAssertEqual(LeadTags(quoteSentDay: "2026-11-08", firstCallToDo: false).quoteSentLabel(now: now, timeZone: paris),
                       "Devis - Devis envoyé - auj.")
        XCTAssertNil(LeadTags.none.quoteSentLabel(now: now, timeZone: paris))
    }

    /// 08/11/2026 à 12:00 (heure de Paris).
    static let now = Date(timeIntervalSince1970: 1_794_135_600)

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
        XCTAssertEqual(tags.quoteSentLabel(now: now, timeZone: paris),
                       "Devis - Devis SEO mis à jour renvoyé - 3j\nDevis - Devis SEO envoyé - 5j")
        XCTAssertEqual(tags.quoteLines(now: now, timeZone: paris).map(\.title), ["Devis SEO mis à jour renvoyé", "Devis SEO envoyé"])

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
        let tags = try await LeadTagsLoader(client: client(transport)).load(for: item(), typeNames: names, timeZone: paris,
                                                                            now: Self.now)
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
        let tags = try await LeadTagsLoader(client: client(transport)).load(for: item(), typeNames: names, timeZone: paris,
                                                                            now: Self.now)
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
        XCTAssertNil(LeadTagRules.signedExcerpt(in: "Hello, c'est signé ça ?"), "question")
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
        XCTAssertNil(tags.quoteSentLabel(now: now, timeZone: paris), "signé : plus d'étiquette")
        XCTAssertTrue(tags.isEmpty)
        XCTAssertFalse(TagFilter.quoteSent.matches(tags))
    }

    func testKickoffMeansSigned() async throws {
        let activities = """
        {"success":true,"data":[
          {"id":41,"subject":"rdv de lancement SEO effectué","type":"call_effectue","due_date":"2026-01-27","done":true,"deal_id":100,"person_id":200},
          {"id":42,"subject":"devis seo mis à jour renvoyé","type":"devis_envoy","due_date":"2025-10-06","done":true,"deal_id":100,"person_id":200}
        ]}
        """
        let transport = MockTransport([
            "GET /api/v2/activities?deal_id=100": .init(status: 200, body: activities),
            "GET /api/v1/notes": .init(status: 200, body: #"{"success":true,"data":[]}"#),
        ])
        let tags = try await LeadTagsLoader(client: client(transport)).load(for: item(), typeNames: names, timeZone: paris,
                                                                            now: Self.now)
        XCTAssertTrue(tags.isSigned)
        XCTAssertEqual(tags.signature?.text, "rdv de lancement SEO effectué")
        XCTAssertTrue(tags.isEmpty, "devis signé, déjà parlé : aucune étiquette")
    }

    func testKickoffRule() {
        func done(_ subject: String) -> Activity {
            Activity(id: 1, subject: subject, type: "task", dueDate: "2026-01-27", dueTime: nil, dealID: 100, personID: nil,
                     orgID: nil, done: true)
        }
        XCTAssertTrue(LeadTagRules.isKickoff(done("rdv de lancement SEO effectué")))
        XCTAssertTrue(LeadTagRules.isKickoff(done("Kick-off projet")))
        XCTAssertTrue(LeadTagRules.isKickoff(done("Call onboarding Google Ads")))
        XCTAssertTrue(LeadTagRules.isKickoff(done("Réunion de démarrage TMA")))
        XCTAssertFalse(LeadTagRules.isKickoff(done("lancement des campagnes")))
        XCTAssertFalse(LeadTagRules.isKickoff(done("Relancer pour signer")))
    }

    func testTagFilter() {
        let pending = LeadTags(quoteSentDay: "2026-11-03", firstCallToDo: false)
        let neverCalled = LeadTags(quotes: [], firstCallToDo: true)
        XCTAssertTrue(TagFilter.quoteSent.matches(pending))
        XCTAssertFalse(TagFilter.quoteSent.matches(neverCalled))
        XCTAssertTrue(TagFilter.firstCall.matches(neverCalled))
        XCTAssertFalse(TagFilter.firstCall.matches(pending))
        XCTAssertTrue(TagFilter.all.matches(.none))
        XCTAssertEqual(TagFilter.allCases.map(\.label), ["Toutes", "En signature", "Devis envoyé", "Devis à faire", "Accès en attente", "RDV à venir",
                                                        "1er call à faire"])
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
        XCTAssertEqual(tags.quoteSentLabel(now: now, timeZone: paris),
                       "Devis - Devis MEV envoyé - 5j\nDevis - Maj devis envoyée - 69j")
    }

    func testSignedFieldFromDeal() async throws {
        let transport = MockTransport([
            "GET /api/v2/activities": .init(status: 200, body: #"{"success":true,"data":[]}"#),
            "GET /api/v1/notes": .init(status: 200, body: #"{"success":true,"data":[]}"#),
        ])
        let deal = DealSummary(id: 100, title: "Site", orgID: nil, personID: 200, score: nil, status: "open",
                               signedDate: "2026-09-07")
        let tags = try await LeadTagsLoader(client: client(transport)).load(for: item(deal: deal), typeNames: names, timeZone: paris,
                                                                            now: Self.now)
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
        let tags = try await LeadTagsLoader(client: client(transport)).load(for: item(), typeNames: names, timeZone: paris,
                                                                            now: Self.now)
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
        XCTAssertNil(tags.quoteSentLabel(now: now, timeZone: paris), "affaire gagnée : plus d'étiquette")
        XCTAssertTrue(tags.isEmpty)

        let lost = DealSummary(id: 100, title: "Site", orgID: nil, personID: 200, score: nil, status: "lost")
        let none = try await LeadTagsLoader(client: client(transport)).load(for: item(deal: lost), typeNames: names, timeZone: paris)
        XCTAssertEqual(none, .none)
        let count = await transport.recorded.count
        XCTAssertEqual(count, 0, "affaire close : aucune requête")
    }

    // MARK: Retours d'Yves du 08/11/2026 (données fictives)

    static func mail(_ id: Int, _ time: String, from: String, to: [String], cc: [String] = [], subject: String,
                     snippet: String, attachments: [String] = []) -> String {
        func parties(_ list: [String]) -> String { list.map { #"{"email_address":"\#($0)"}"# }.joined(separator: ",") }
        let files = attachments.map { #"{"name":"\#($0)","inline_flag":false,"file_type":"application/pdf"}"# }
            .joined(separator: ",")
        return #"{"object":"mailMessage","data":{"id":\#(id),"message_time":"\#(time)","from":[\#(parties([from]))],"#
            + #""to":[\#(parties(to))],"cc":[\#(parties(cc))],"subject":"\#(subject)","snippet":"\#(snippet)","#
            + #""has_real_attachments_flag":\#(attachments.isEmpty ? 0 : 1),"draft_flag":0,"attachments":[\#(files)]}}"#
    }

    static func mails(_ items: [String]) -> String {
        #"{"success":true,"data":[\#(items.joined(separator: ","))],"additional_data":{"pagination":{"more_items_in_collection":false}}}"#
    }

    func transport(activities: String, mails: String) -> MockTransport {
        MockTransport([
            "GET /api/v2/activities?deal_id=100": .init(status: 200, body: activities),
            "GET /api/v2/activities?person_id=200": .init(status: 200, body: #"{"success":true,"data":[]}"#),
            "GET /api/v1/notes": .init(status: 200, body: #"{"success":true,"data":[]}"#),
            "GET /api/v1/deals/100/mailMessages": .init(status: 200, body: mails),
        ])
    }

    /// Tâche « envoyer les devis » cochée et proposition envoyée par un partenaire : pas de devis de l'agence.
    func testTodoTaskAndPartnerProposalAreNotQuotes() async throws {
        let activities = """
        {"success":true,"data":[
          {"id":61,"subject":"Client Test : envoyer les 2 devis (option A / option B)","type":"task","due_date":"2026-11-06","done":true,"deal_id":100,"person_id":200},
          {"id":62,"subject":"Call effectué","type":"call_effectue","due_date":"2026-11-05","done":true,"deal_id":100,"person_id":200}
        ]}
        """
        let mails = Self.mails([
            Self.mail(3001, "2026-11-06T16:37:31.000Z", from: "partenaire@exemple.fr", to: ["moi@example.com", "client@example.org"],
                      subject: "Re: DEVIS boutique", snippet: "Vous trouverez en pj une présentation avec les tarifs",
                      attachments: ["Client-Proposition-Boutique.pdf"]),
        ])
        let tags = try await LeadTagsLoader(client: client(transport(activities: activities, mails: mails)))
            .load(for: item(), typeNames: names, timeZone: paris, now: Self.now, myEmail: "moi@example.com")
        XCTAssertTrue(tags.quotes.isEmpty)
        XCTAssertNil(tags.quoteSentLabel(now: Self.now, timeZone: paris))
        XCTAssertTrue(tags.isEmpty)
    }

    /// Dernier devis vieux de plus d'un an (signé dans l'yntranet seulement) : plus « en attente ».
    func testOldQuoteIsNoLongerPending() async throws {
        let activities = """
        {"success":true,"data":[
          {"id":71,"subject":"Call effectué","type":"call_effectue","due_date":"2026-04-30","done":true,"deal_id":100,"person_id":200},
          {"id":72,"subject":"Devis connecteur envoyé","type":"devis_envoy","due_date":"2025-09-15","done":true,"deal_id":100,"person_id":200}
        ]}
        """
        let tags = try await LeadTagsLoader(client: client(transport(activities: activities, mails: Self.mails([]))))
            .load(for: item(), typeNames: names, timeZone: paris, now: Self.now, myEmail: "moi@example.com")
        XCTAssertTrue(tags.quotes.isEmpty)
        XCTAssertNil(tags.quoteSentLabel(now: Self.now, timeZone: paris))
        XCTAssertTrue(tags.isEmpty)
        XCTAssertEqual(LeadTags.pendingWindowDays, 180)
    }

    /// Devis envoyé par un collègue par e-mail, « Bon pour accord » du client puis mail de facturation « À la suite de
    /// la signature du bon de commande » : signé, plus d'étiquette.
    func testQuoteAndSignatureByMail() async throws {
        let activities = """
        {"success":true,"data":[
          {"id":81,"subject":"Call effectué","type":"call_effectue","due_date":"2026-10-28","done":true,"deal_id":100,"person_id":200},
          {"id":82,"subject":"devis correctifs envoyé","type":"devis_envoy","due_date":"2026-01-12","done":true,"deal_id":100,"person_id":200}
        ]}
        """
        let mails = Self.mails([
            Self.mail(4005, "2026-10-15T09:00:00.000Z", from: "compta@example.com", to: ["client@example.org"],
                      subject: "RE: Montée de version",
                      snippet: "Bonjour, A la suite de la signature du bon de commande N° BDC-0001-TST, notre facture, correspondant au 1er acompte, vous a été envoyée."),
            Self.mail(4004, "2026-10-14T16:00:00.000Z", from: "client@example.org", to: ["moi@example.com", "collegue@example.com"],
                      subject: "Re: Site piraté", snippet: "Bonjour, Bon pour accord. Vous pouvez faire le nécessaire."),
            Self.mail(4003, "2026-10-14T10:00:00.000Z", from: "collegue@example.com", to: ["client@example.org"], cc: ["moi@example.com"],
                      subject: "Montée de version", snippet: "Hello, tu trouveras en pièce jointe le devis concernant la montée de version.",
                      attachments: ["Proposition_AGENCE_pour_CLIENT-Mise_à_jour-9.2.pdf"]),
            Self.mail(4002, "2026-10-14T09:00:00.000Z", from: "collegue@example.com", to: ["moi@example.com"],
                      subject: "Re: Montée de version", snippet: "Hello, c'est signé ça ?"),
            Self.mail(4001, "2026-10-03T08:00:00.000Z", from: "factures@exemple.com", to: ["client@example.org"],
                      subject: "Votre facture est disponible", snippet: "Voici votre dernière facture",
                      attachments: ["Facture-CLIENT-AGENCE-0001.pdf"]),
        ])
        let tags = try await LeadTagsLoader(client: client(transport(activities: activities, mails: mails)))
            .load(for: item(), typeNames: names, timeZone: paris, now: Self.now, myEmail: "Moi@Example.com")
        XCTAssertEqual(tags.quotes.map(\.id), [4003], "le devis de janvier a plus de 6 mois ; la facture n'est pas un devis")
        XCTAssertEqual(tags.quotes.first?.source, .mail)
        XCTAssertEqual(tags.signature?.source, .mail)
        XCTAssertEqual(tags.signature?.day, "2026-10-15")
        XCTAssertTrue(tags.signature?.text.contains("signature du bon de commande") ?? false)
        XCTAssertTrue(tags.isSigned)
        XCTAssertNil(tags.quoteSentLabel(now: Self.now, timeZone: paris))
        XCTAssertTrue(tags.isEmpty)
    }

    /// Devis envoyé par e-mail le 3 novembre, sans activité : c'est lui qui compte ; l'ancien devis (signé) est ignoré.
    func testLatestQuoteSentByMail() async throws {
        let activities = """
        {"success":true,"data":[
          {"id":91,"subject":"Call effectué","type":"call_effectue","due_date":"2026-03-01","done":true,"deal_id":100,"person_id":200},
          {"id":92,"subject":"devis lot 2 envoyé","type":"devis_envoy","due_date":"2026-02-02","done":true,"deal_id":100,"person_id":200}
        ]}
        """
        let mails = Self.mails([
            Self.mail(5003, "2026-11-08T08:00:00.000Z", from: "moi@example.com", to: ["client@example.org"],
                      subject: "Re: Montée de version - Proposition",
                      snippet: "Bonjour, je me permets de revenir vers vous suite au devis envoyé la semaine dernière."),
            Self.mail(5002, "2026-11-03T20:14:00.000Z", from: "moi@example.com", to: ["client@example.org"],
                      subject: "Montée de version - Proposition", snippet: "Bonjour, comme convenu, voici le devis pour la montée de version.",
                      attachments: ["Proposition_AGENCE_pour_CLIENT-Mise_à_jour-9.2.pdf", "image001.png"]),
            Self.mail(5001, "2026-05-22T09:00:00.000Z", from: "compta@example.com", to: ["client@example.org"],
                      subject: "Lot 2", snippet: "Bonjour, suite à la signature du bon de commande, voici notre facture d'acompte."),
        ])
        let tags = try await LeadTagsLoader(client: client(transport(activities: activities, mails: mails)))
            .load(for: item(), typeNames: names, timeZone: paris, now: Self.now, myEmail: "moi@example.com")
        XCTAssertEqual(tags.quotes.count, 1)
        let quote = try XCTUnwrap(tags.quotes.first)
        XCTAssertEqual(quote.source, .mail)
        XCTAssertEqual(quote.day, "2026-11-03")
        XCTAssertEqual(quote.dateText, "3 novembre à 21:14")
        XCTAssertEqual(quote.note, "Pièce jointe : Proposition_AGENCE_pour_CLIENT-Mise_à_jour-9.2.pdf")
        XCTAssertEqual(tags.signature?.day, "2026-05-22", "signature du lot 2, avant le nouveau devis")
        XCTAssertFalse(tags.isSigned)
        XCTAssertEqual(tags.quoteSentLabel(now: Self.now, timeZone: paris), "Devis - MEV - Proposition - 5j")
    }

    /// Même jour qu'une activité « Devis envoyé » : l'e-mail n'ajoute pas un deuxième devis.
    func testMailQuoteSameDayAsActivityCountsOnce() async throws {
        let activities = """
        {"success":true,"data":[
          {"id":95,"subject":"Devis montée de version envoyé","type":"devis_envoy","due_date":"2026-11-03","done":true,"deal_id":100,"person_id":200},
          {"id":96,"subject":"Call effectué","type":"call_effectue","due_date":"2026-10-28","done":true,"deal_id":100,"person_id":200}
        ]}
        """
        let mails = Self.mails([
            Self.mail(5102, "2026-11-03T20:14:00.000Z", from: "moi@example.com", to: ["client@example.org"],
                      subject: "Montée de version - Proposition", snippet: "Voici le devis.",
                      attachments: ["Proposition_AGENCE_pour_CLIENT.pdf"]),
        ])
        let tags = try await LeadTagsLoader(client: client(transport(activities: activities, mails: mails)))
            .load(for: item(), typeNames: names, timeZone: paris, now: Self.now, myEmail: "moi@example.com")
        XCTAssertEqual(tags.quotes.map(\.id), [95])
    }

    func testMailRules() throws {
        func mail(from: String, to: [String] = ["client@example.org"], subject: String = "Objet", snippet: String = "",
                  attachments: [String] = [], flag: Bool? = nil) -> DealMail {
            DealMail(id: 1, subject: subject, snippet: snippet, from: [from], recipients: to,
                     hasAttachments: flag ?? !attachments.isEmpty, attachmentNames: attachments, sentAt: nil)
        }
        let own = "example.com"
        XCTAssertEqual(MailRules.quoteDocuments(in: mail(from: "moi@example.com", attachments: ["Devis_refonte.pdf"]), ownDomain: own),
                       "Devis_refonte.pdf")
        XCTAssertEqual(MailRules.quoteDocuments(in: mail(from: "moi@example.com", attachments: ["BDC-0001-TST.pdf"]), ownDomain: own),
                       "BDC-0001-TST.pdf")
        XCTAssertNil(MailRules.quoteDocuments(in: mail(from: "moi@example.com", to: ["collegue@example.com"],
                                                       attachments: ["Devis_refonte.pdf"]), ownDomain: own), "interne")
        XCTAssertNil(MailRules.quoteDocuments(in: mail(from: "moi@example.com", attachments: ["Facture-CLIENT-0001.pdf"]), ownDomain: own))
        XCTAssertNil(MailRules.quoteDocuments(in: mail(from: "moi@example.com", attachments: ["client.fr - Audit de sécurité V2.pdf"]),
                                              ownDomain: own))
        XCTAssertNil(MailRules.quoteDocuments(in: mail(from: "moi@example.com", attachments: ["image001.png"]), ownDomain: own))
        XCTAssertNil(MailRules.quoteDocuments(in: mail(from: "client@example.org", to: ["moi@example.com"],
                                                       attachments: ["Devis_concurrent.pdf"]), ownDomain: own), "écrit par le client")
        XCTAssertEqual(MailRules.quoteDocuments(in: mail(from: "moi@example.com", subject: "Devis refonte", flag: true), ownDomain: own),
                       "Devis refonte", "pièce jointe sans nom connu : l'objet parle d'un devis")
        XCTAssertNil(MailRules.quoteDocuments(in: mail(from: "moi@example.com", subject: "Devis refonte"), ownDomain: own),
                     "sans pièce jointe")

        XCTAssertNotNil(MailRules.signatureExcerpt(in: mail(from: "client@example.org", to: ["moi@example.com"],
                                                            snippet: "Bonjour, Bon pour accord. Vous pouvez faire le nécessaire."),
                                                   ownDomain: own))
        XCTAssertNil(MailRules.signatureExcerpt(in: mail(from: "moi@example.com",
                                                         snippet: "Merci de nous retourner le devis avec la mention bon pour accord"),
                                                ownDomain: own), "« bon pour accord » demandé par l'agence")
        XCTAssertNotNil(MailRules.signatureExcerpt(in: mail(from: "client@example.org", snippet: "Les documents ont été signés ce jour"),
                                                   ownDomain: own))
        XCTAssertNotNil(MailRules.signatureExcerpt(in: mail(from: "client@example.org",
                                                            snippet: "Nous prenons acte de votre proposition et nous validons la proposition dans son ensemble"),
                                                   ownDomain: own))
        XCTAssertNil(MailRules.signatureExcerpt(in: mail(from: "client@example.org", snippet: "Les documents ont été signés ?"),
                                                ownDomain: own), "question")
        XCTAssertNil(MailRules.signatureExcerpt(in: mail(from: "client@example.org", snippet: "Le devis n'est pas encore signé"),
                                                ownDomain: own))
        XCTAssertNil(MailRules.signatureExcerpt(
            in: mail(from: "client@example.org", snippet: "Merci ! Le 3 nov. 2026 à 21:14, Moi Test <moi@example.com> a écrit : A la suite de la signature du bon de commande"),
            ownDomain: own), "citation du message précédent ignorée")
    }

    func testMailDateWithMilliseconds() throws {
        let json = try decode(Self.mail(1, "2026-11-03T19:14:30.000Z", from: "moi@example.com", to: ["client@example.org"],
                                        subject: "Objet", snippet: "Texte"))
        let mail = try XCTUnwrap(DealMail(json: json))
        XCTAssertEqual(mail.day(timeZone: paris), "2026-11-03")
        XCTAssertNotNil(FrenchFormat.parseInstant("2026-11-03T19:14:30Z"))
    }
}
