import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PipedriveKit

/// Score saisi à la main, cadenas, retour en automatique (demande d'Yves du 25/11/2026). Codes et valeurs fictifs.
final class ManualScoreTests: XCTestCase {
    let config = PipedriveConfiguration(companyDomain: "test", apiToken: "jeton-factice")

    let fields = [
        FieldDefinition(code: "title", name: "Titre", type: "varchar", isCustom: false),
        FieldDefinition(code: "code_score", name: "Score priorisation", type: "double", isCustom: true),
        FieldDefinition(code: "code_source", name: "Source de la qualification", type: "enum", isCustom: true,
                        options: [FieldOption(id: 11, label: "Extraction"), FieldOption(id: 12, label: "Manuel")]),
    ]

    func testFieldsFoundByName() throws {
        let score = try XCTUnwrap(ScoreFields(fields: fields))
        XCTAssertEqual(score.scoreCode, "code_score")
        XCTAssertEqual(score.sourceCode, "code_source")
        XCTAssertEqual(score.manualOptionID, 12)
        XCTAssertEqual(score.automaticOptionID, 11)

        XCTAssertEqual(score.manualValues(score: 72), ["code_score": .int(72), "code_source": .int(12)])
        XCTAssertEqual(score.manualValues(score: 62.5), ["code_score": .double(62.5), "code_source": .int(12)])
        XCTAssertEqual(score.automaticValues, ["code_source": .int(11)])
        XCTAssertEqual(score.restoreValues(score: 40, manual: false), ["code_score": .int(40), "code_source": .int(11)])
        XCTAssertEqual(score.restoreValues(score: nil, manual: true), ["code_score": .null, "code_source": .int(12)])

        // Sans champ « Source de la qualification » : le score seul ; sans « Score priorisation » : rien.
        let scoreOnly = try XCTUnwrap(ScoreFields(fields: Array(fields.prefix(2))))
        XCTAssertEqual(scoreOnly.manualValues(score: 50), ["code_score": .int(50)])
        XCTAssertNil(scoreOnly.automaticValues)
        XCTAssertNil(ScoreFields(fields: [fields[0], fields[2]]))
    }

    func testScoreInput() {
        XCTAssertEqual(ScoreInput.parse("72"), 72)
        XCTAssertEqual(ScoreInput.parse(" 62,5 "), 62.5)
        XCTAssertEqual(ScoreInput.parse("62.5"), 62.5)
        XCTAssertEqual(ScoreInput.parse("0"), 0)
        XCTAssertEqual(ScoreInput.parse("100"), 100)
        XCTAssertNil(ScoreInput.parse("101"))
        XCTAssertNil(ScoreInput.parse("-3"))
        XCTAssertNil(ScoreInput.parse("abc"))
        XCTAssertNil(ScoreInput.parse(""))
    }

    func testManualFlagReadOnTheDeal() throws {
        func deal(_ source: String) throws -> DealSummary? {
            DealSummary(json: try decode(#"{"id":5,"title":"Site","custom_fields":{"code_score":72,"code_source":\#(source)}}"#),
                        scoreCode: "code_score", sourceCode: "code_source", manualOptionID: 12)
        }
        XCTAssertEqual(try deal("12")?.scoreIsManual, true)
        XCTAssertEqual(try deal(#""12""#)?.scoreIsManual, true)
        XCTAssertEqual(try deal(#"{"id":12,"label":"Manuel"}"#)?.scoreIsManual, true)
        XCTAssertEqual(try deal("11")?.scoreIsManual, false)
        XCTAssertEqual(try deal("null")?.scoreIsManual, false)
        XCTAssertEqual(try deal("12")?.score, 72)
        let locked = try XCTUnwrap(try deal("11")).with(score: 80, manual: true)
        XCTAssertEqual(locked.score, 80)
        XCTAssertTrue(locked.scoreIsManual)
        XCTAssertEqual(locked.title, "Site")
    }

    /// Le chargement de la liste lit la source avec le score ; l'écriture passe par `PATCH /api/v2/deals/{id}`.
    func testFeedReadsTheSourceAndUpdateWritesBothFields() async throws {
        let transport = MockTransport([
            "GET /api/v2/activities": .init(status: 200, body: Fixtures.activities),
            "GET /api/v2/dealFields": .init(status: 200, body: """
            {"success":true,"data":[
              {"field_name":"Score priorisation","field_code":"code_score","field_type":"double","is_custom_field":true},
              {"field_name":"Source de la qualification","field_code":"code_source","field_type":"enum","is_custom_field":true,
               "options":[{"id":11,"label":"Extraction"},{"id":12,"label":"Manuel"}]}
            ],"additional_data":{"next_cursor":null}}
            """),
            "GET /api/v2/deals": .init(status: 200, body: """
            {"success":true,"data":[
              {"id":100,"title":"Site vitrine","org_id":300,"person_id":200,"custom_fields":{"code_score":42.5,"code_source":12}},
              {"id":101,"title":"Campagne SEA","org_id":302,"person_id":201,"custom_fields":{"code_score":87,"code_source":11}}
            ]}
            """),
            "GET /api/v2/persons": .init(status: 200, body: Fixtures.persons),
            "GET /api/v2/organizations": .init(status: 200, body: Fixtures.organizations),
            "PATCH /api/v2/deals/100": .init(status: 200, body: #"{"success":true,"data":{"id":100}}"#),
        ])
        let client = PipedriveClient(configuration: config, transport: transport)
        let loader = ActivityFeedLoader(client: client)
        let items = try await loader.load(ownerIDs: [7], filter: ActivityDateFilter(from: nil, to: "2026-11-07"),
                                          timeZone: paris, now: ClientTests.seventhNoon)
        XCTAssertEqual(items.first { $0.deal?.id == 100 }?.scoreIsManual, true)
        XCTAssertEqual(items.first { $0.deal?.id == 101 }?.scoreIsManual, false)
        let recorded = await transport.recorded
        let dealsRequest = try XCTUnwrap(recorded.first { $0.url?.path == "/api/v2/deals" })
        XCTAssertEqual(query(dealsRequest, "custom_fields"), "code_score,code_source")

        let fields = try await loader.scoreFields()
        let score = try XCTUnwrap(fields)
        try await client.updateDealFields(id: 100, score.manualValues(score: 72))
        let afterUpdate = await transport.recorded
        let patch = try XCTUnwrap(afterUpdate.last)
        XCTAssertEqual(patch.httpMethod, "PATCH")
        XCTAssertEqual(patch.url?.path, "/api/v2/deals/100")
        let sent = try decode(String(decoding: try XCTUnwrap(patch.httpBody), as: UTF8.self))
        XCTAssertEqual(sent["custom_fields"]["code_score"].intValue, 72)
        XCTAssertEqual(sent["custom_fields"]["code_source"].intValue, 12)
    }

    func testWidgetAlertCarriesTheLock() throws {
        let deal = DealSummary(id: 100, title: "Site", orgID: nil, personID: nil, score: 72, scoreIsManual: true)
        let activity = Activity(id: 1, subject: "Relancer", type: "task", dueDate: "2026-11-07", dueTime: nil,
                                dealID: 100, personID: nil, orgID: nil, done: false)
        let alert = WidgetAlert(item: ActivityItem(activity: activity, organizationName: "Entreprise Alpha", person: nil,
                                                   deal: deal))
        XCTAssertTrue(alert.isManualScore)
        // Alertes gardées par les premiers widgets (sans l'information) : pas de cadenas.
        let old = #"{"id":1,"company":"Entreprise Alpha","text":"Relancer","score":72}"#
        let decoded = try JSONDecoder().decode(WidgetAlert.self, from: Data(old.utf8))
        XCTAssertFalse(decoded.isManualScore)
    }
}
