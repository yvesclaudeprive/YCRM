import XCTest
@testable import PipedriveKit

/// Analyse des devis écrite par Claude dans le champ « Devis en attente » (données fictives).
final class QuoteAnalysisTests: XCTestCase {
    static let now = Date(timeIntervalSince1970: 1_794_135_600) // 08/11/2026 à 12:00

    static let sample = """
    EN SIGNATURE
    • Montée de version | 06/11/2026 | DocuSign consulté par le client le 07/11/2026
    DEVIS ENVOYÉS (2)
    • Refonte du site | 16/04/2026 | relancé le 03/11/2026, rien de signé
    • Audit sécurité | 03/11/2026 | envoyé par mail avec la proposition en pièce jointe
    SIGNÉS
    • TMA | 11/08/2026 | projet signé
    ABANDONNÉS
    • Aucun
    COMMENTAIRES
    • 08/11/2026 : « la TMA est signée, la refonte non » → pris en compte
    Analyse Claude du 08/11/2026 à 13:17
    """

    func testParse() throws {
        let analysis = try XCTUnwrap(QuoteAnalysis(text: Self.sample))
        XCTAssertEqual(analysis.entries(.signing).map(\.title), ["Montée de version"])
        XCTAssertEqual(analysis.entries(.sent).map(\.title), ["Audit sécurité", "Refonte du site"], "le plus récent d'abord")
        XCTAssertEqual(analysis.entries(.sent).last?.day, "2026-04-16")
        XCTAssertEqual(analysis.entries(.sent).last?.detail, "relancé le 03/11/2026, rien de signé")
        XCTAssertEqual(analysis.entries(.signed).map(\.title), ["TMA"])
        XCTAssertTrue(analysis.entries(.abandoned).isEmpty, "« Aucun » n'est pas un devis")
        XCTAssertEqual(analysis.comments, ["08/11/2026 : « la TMA est signée, la refonte non » → pris en compte"])
        XCTAssertEqual(analysis.footer, "Analyse Claude du 08/11/2026 à 13:17")
    }

    func testMultipleTagFilters() throws {
        let analysis = try XCTUnwrap(QuoteAnalysis(text: "EN SIGNATURE\n• TMA | 06/11/2026 | DocuSign envoyé"))
        let signing = LeadTags(analysis: analysis, firstCallToDo: false, now: Self.now, timeZone: paris)
        let neverCalled = LeadTags(quotes: [], firstCallToDo: true)
        let nothing = LeadTags.none
        let both: Set<TagFilter> = [.signing, .firstCall]
        XCTAssertTrue(both.matches(signing))
        XCTAssertTrue(both.matches(neverCalled))
        XCTAssertFalse(both.matches(nothing))
        XCTAssertFalse(Set<TagFilter>([.quoteSent]).matches(signing))
        XCTAssertTrue(Set<TagFilter>().isAll)
        XCTAssertTrue(Set<TagFilter>([.all, .signing]).isAll)
        XCTAssertTrue(Set<TagFilter>().matches(nothing))
        XCTAssertEqual(Set<TagFilter>([.firstCall, .signing]).label, "En signature ou 1er call à faire")
        XCTAssertEqual(Set<TagFilter>().label, "Toutes")
    }

    func testAccessPending() throws {
        let text = "ACCÈS EN ATTENTE\n• FTP + back-office | 09/07/2026 | demandés par Mehdi, relancés le 05/11/2026\nAnalyse Claude du 08/11/2026 à 16:00"
        let analysis = try XCTUnwrap(QuoteAnalysis(text: text))
        XCTAssertEqual(analysis.entries(.access).map(\.title), ["FTP + back-office"])
        let tags = LeadTags(analysis: analysis, firstCallToDo: false, now: Self.now, timeZone: paris)
        XCTAssertTrue(tags.hasAccessPending)
        XCTAssertFalse(tags.isEmpty)
        XCTAssertFalse(tags.hasPendingQuote, "un accès n'est pas un devis")
        XCTAssertEqual(tags.accessLines(now: Self.now, timeZone: paris).map(\.text), ["Accès - FTP + back-office - 122j"])
        XCTAssertTrue(TagFilter.access.matches(tags))
        XCTAssertFalse(TagFilter.quoteSent.matches(tags))
    }

    func testQuoteToDo() throws {
        let text = "DEVIS À FAIRE\n• Montée de version PrestaShop | 28/10/2026 | demandé en rendez-vous, promis pour le 15/11\n" +
            "ACCÈS EN ATTENTE\n• FTP | 09/07/2026 | demandé\nAnalyse Claude du 08/11/2026 à 16:00"
        let analysis = try XCTUnwrap(QuoteAnalysis(text: text))
        XCTAssertEqual(analysis.entries(.toDo).map(\.title), ["Montée de version PrestaShop"])
        let tags = LeadTags(analysis: analysis, firstCallToDo: false, now: Self.now, timeZone: paris)
        XCTAssertTrue(tags.hasQuoteToDo)
        XCTAssertFalse(tags.hasPendingQuote, "un devis à faire n'est pas un devis envoyé")
        XCTAssertFalse(tags.isEmpty)
        XCTAssertFalse(tags.isSigned)
        XCTAssertEqual(tags.toDoLines(now: Self.now, timeZone: paris).map(\.text), ["Devis à faire - MEV PrestaShop - 11j"])
        XCTAssertTrue(TagFilter.quoteToDo.matches(tags))
        XCTAssertFalse(TagFilter.quoteSent.matches(tags))
        XCTAssertTrue(Set<TagFilter>([.quoteToDo, .firstCall]).matches(tags))
        XCTAssertEqual(Set<TagFilter>([.quoteToDo, .signing]).label, "En signature ou Devis à faire")
        XCTAssertEqual(QuoteAnalysis.Status.toDo.title, "Devis à faire")
    }

    func testShortNamesInTags() throws {
        XCTAssertEqual(LeadTags.shortTitle("Google Analytics 4 + Google Search Console"), "GA4 + GSC")
        XCTAssertEqual(LeadTags.shortTitle("google analytics, search console et Google Ads"), "GA4, GSC et Google Ads")
        XCTAssertEqual(LeadTags.shortTitle("Serach Console"), "GSC")
        XCTAssertEqual(LeadTags.shortTitle("GA 4"), "GA4")
        XCTAssertEqual(LeadTags.shortTitle("Adobe Analytics"), "Adobe Analytics")
        XCTAssertEqual(LeadTags.shortTitle("Montée de version PrestaShop 9.2"), "MEV PrestaShop 9.2")
        XCTAssertEqual(LeadTags.shortTitle("Refonte ou montee de version"), "Refonte ou MEV")
        XCTAssertEqual(LeadTags.shortTitle("Montées de versions"), "MEV")
        let text = "ACCÈS EN ATTENTE\n• Google Analytics + Search Console | 09/07/2026 | demandés\nAnalyse Claude du 08/11/2026 à 16:00"
        let tags = LeadTags(analysis: try XCTUnwrap(QuoteAnalysis(text: text)), firstCallToDo: false, now: Self.now, timeZone: paris)
        XCTAssertEqual(tags.accessLines(now: Self.now, timeZone: paris).map(\.text), ["Accès - GA4 + GSC - 122j"])
    }

    func testFieldName() {
        XCTAssertTrue(ActivityFeedLoader.isQuoteAnalysisField("Devis en attente (claude)"))
        XCTAssertTrue(ActivityFeedLoader.isQuoteAnalysisField("Devis en attente"))
        XCTAssertTrue(ActivityFeedLoader.isQuoteAnalysisField(ActivityFeedLoader.quoteAnalysisFieldName))
        XCTAssertFalse(ActivityFeedLoader.isQuoteAnalysisField("Devis envoyé"))
    }

    func testEmptyFieldIsNotAnalyzed() {
        XCTAssertNil(QuoteAnalysis(text: nil))
        XCTAssertNil(QuoteAnalysis(text: "  \n "))
    }

    func testBulletIsNeverAHeaderAndFreeText() throws {
        let analysis = try XCTUnwrap(QuoteAnalysis(text: "Devis envoyés :\n- Devis envoyé\n- Site vitrine envoyé le 02/11/2026"))
        XCTAssertEqual(analysis.entries(.sent).map(\.title), ["Site vitrine envoyé le 02/11/2026", "Devis envoyé"])
        XCTAssertEqual(analysis.entries(.sent).first?.day, "2026-11-02")
    }

    func testTagsFromAnalysis() throws {
        let analysis = try XCTUnwrap(QuoteAnalysis(text: Self.sample))
        let tags = LeadTags(analysis: analysis, firstCallToDo: false, now: Self.now, timeZone: paris)
        XCTAssertEqual(tags.signingLabel(now: Self.now, timeZone: paris), "En signature - MEV - 2j")
        XCTAssertEqual(tags.quoteSentLabel(now: Self.now, timeZone: paris),
                       "Devis - Audit sécurité - 5j\nDevis - Refonte du site - 206j")
        let line = try XCTUnwrap(tags.quoteLines(now: Self.now, timeZone: paris).first)
        XCTAssertEqual(line.prefix, "Devis")
        XCTAssertEqual(line.title, "Audit sécurité")
        XCTAssertEqual(line.age, "5j")
        XCTAssertTrue(TagFilter.signing.matches(tags))
        XCTAssertTrue(TagFilter.quoteSent.matches(tags))
        XCTAssertFalse(tags.isSigned)
        XCTAssertEqual(tags.quotes.first?.source, .analysis)

        let signedOnly = try XCTUnwrap(QuoteAnalysis(text: "SIGNÉS\n• TMA | 11/08/2026 | projet signé"))
        let done = LeadTags(analysis: signedOnly, firstCallToDo: false, now: Self.now, timeZone: paris)
        XCTAssertTrue(done.isEmpty)
        XCTAssertTrue(done.isSigned)
        XCTAssertNil(done.quoteSentLabel(now: Self.now, timeZone: paris))
        XCTAssertNil(done.signingLabel(now: Self.now, timeZone: paris))
    }

    func client(_ transport: MockTransport) -> PipedriveClient {
        PipedriveClient(configuration: .init(companyDomain: "test", apiToken: "t"), transport: transport)
    }

    func item(_ deal: DealSummary) -> ActivityItem {
        let activity = Activity(id: 9, subject: "Relancer", type: "task", dueDate: "2026-11-08", dueTime: nil,
                                dealID: 100, personID: 200, orgID: nil, done: false)
        return ActivityItem(activity: activity, organizationName: "Entreprise Alpha", person: nil, deal: deal)
    }

    /// Avec l'analyse de Claude : ni règles locales ni e-mails ; seul « 1er call à faire » est vérifié.
    func testLoaderUsesAnalysis() async throws {
        let transport = MockTransport([
            "GET /api/v2/activities?deal_id=100": .init(status: 200, body: """
            {"success":true,"data":[{"id":1,"subject":"Call effectué","type":"call_effectue","due_date":"2026-11-02","done":true,"deal_id":100}]}
            """),
        ])
        let deal = DealSummary(id: 100, title: "Refonte", orgID: nil, personID: 200, score: nil, status: "open",
                               quoteAnalysis: "DEVIS ENVOYÉS\n• Refonte du site | 16/04/2026 | rien de signé")
        let tags = try await LeadTagsLoader(client: client(transport))
            .load(for: item(deal), typeNames: [:], timeZone: paris, now: Self.now, myEmail: "moi@example.com")
        XCTAssertEqual(tags.quoteSentLabel(now: Self.now, timeZone: paris), "Devis - Refonte du site - 206j",
                       "devis de plus de 6 mois gardé : c'est Claude qui décide")
        XCTAssertFalse(tags.firstCallToDo)
        let paths = await transport.recorded.compactMap { $0.url?.path }
        XCTAssertEqual(paths, ["/api/v2/activities"], "pas de lecture des e-mails ni des notes")
    }

    func testWonDealWithPendingQuoteInAnalysis() async throws {
        let transport = MockTransport([:])
        let deal = DealSummary(id: 100, title: "Refonte", orgID: nil, personID: 200, score: nil, status: "won",
                               quoteAnalysis: "EN SIGNATURE\n• Refonte | 05/11/2026 | DocuSign envoyé\nSIGNÉS\n• TMA | 11/08/2026")
        let tags = try await LeadTagsLoader(client: client(transport))
            .load(for: item(deal), typeNames: [:], timeZone: paris, now: Self.now)
        XCTAssertEqual(tags.signingLabel(now: Self.now, timeZone: paris), "En signature - Refonte - 3j")
        XCTAssertFalse(tags.firstCallToDo)
        let count = await transport.recorded.count
        XCTAssertEqual(count, 0)
    }

    func testDealAnalysisField() throws {
        let code = String(repeating: "b", count: 40)
        let json = try decode("""
        {"id":100,"title":"Refonte","status":"open","custom_fields":{"\(code)":"DEVIS ENVOYÉS\\n• Refonte | 16/04/2026"}}
        """)
        let deal = try XCTUnwrap(DealSummary(json: json, scoreCode: nil, analysisCode: code))
        XCTAssertEqual(QuoteAnalysis(text: deal.quoteAnalysis)?.entries(.sent).first?.title, "Refonte")
        let empty = try XCTUnwrap(DealSummary(json: decode(#"{"id":101,"custom_fields":{"\#(code)":"  "}}"#),
                                              scoreCode: nil, analysisCode: code))
        XCTAssertNil(empty.quoteAnalysis)
    }

    func testAddNoteForClaude() async throws {
        let transport = MockTransport([
            "POST /api/v1/notes": .init(status: 201, body: #"{"success":true,"data":{"id":555}}"#),
            "DELETE /api/v1/notes/555": .init(status: 200, body: #"{"success":true,"data":{"id":555}}"#),
        ])
        let id = try await client(transport).addNote(content: "Pour Claude (YCRM) : test", dealID: 100, personID: 200, orgID: 300)
        XCTAssertEqual(id, 555)
        try await client(transport).deleteNote(id: 555)
        let recorded = await transport.recorded
        let body = try XCTUnwrap(recorded.first?.httpBody)
        let json = try JSONDecoder().decode(JSONValue.self, from: body)
        XCTAssertEqual(json["deal_id"].intValue, 100)
        XCTAssertTrue(json["person_id"].isNull, "la note va sur l'affaire seulement")
        XCTAssertEqual(json["content"].stringValue, "Pour Claude (YCRM) : test")
        XCTAssertEqual(recorded.last?.httpMethod, "DELETE")
    }
}

final class ClaudeNoteTests: XCTestCase {
    func testHTML() {
        XCTAssertEqual(ClaudeNote.html(" La TMA est signée,\nla refonte <non> & rien d'autre \n"),
                       "<b>Pour Claude (YCRM) :</b> La TMA est signée,<br>la refonte &lt;non&gt; &amp; rien d'autre")
        XCTAssertTrue(PlainText.from(html: ClaudeNote.html("test")).hasPrefix(ClaudeNote.prefix))
    }
}
