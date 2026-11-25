import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PipedriveKit

/// Widget de l'écran de gauche (demande d'Yves du 25/11/2026). Données fictives.
final class WidgetFeedTests: XCTestCase {
    let config = PipedriveConfiguration(companyDomain: "test", apiToken: "jeton-factice")
    let seventhNoon = ClientTests.seventhNoon

    func transport() -> MockTransport {
        MockTransport([
            "GET /api/v2/activities": .init(status: 200, body: Fixtures.activities),
            "GET /api/v2/dealFields": .init(status: 200, body: Fixtures.dealFields),
            "GET /api/v2/deals": .init(status: 200, body: Fixtures.deals),
            "GET /api/v2/persons": .init(status: 200, body: Fixtures.persons),
            "GET /api/v2/organizations": .init(status: 200, body: Fixtures.organizations),
            "GET /api/v1/users/me": .init(status: 200, body: #"{"success":true,"data":{"id":7,"name":"Utilisateur Test","email":"test@example.com","active_flag":true}}"#),
        ])
    }

    func testLinks() {
        XCTAssertEqual(YCRMLink.search.absoluteString, "ycrm://search")
        XCTAssertEqual(YCRMLink.destination(of: YCRMLink.search), .search)
        XCTAssertEqual(YCRMLink.destination(of: YCRMLink.home), .home)
        let link = YCRMLink.alert(id: 42)
        XCTAssertEqual(link.absoluteString, "ycrm://alert?id=42")
        XCTAssertEqual(YCRMLink.destination(of: link), .alert(id: 42))
        XCTAssertEqual(YCRMLink.destination(of: URL(string: "ycrm://alert")!), .home, "sans identifiant : la liste")
        // Liens des premiers widgets (fiche Pipedrive) : la liste de l'app.
        XCTAssertEqual(YCRMLink.destination(of: URL(string: "ycrm://open?deal=100&person=200")!), .home)
        XCTAssertNil(YCRMLink.destination(of: URL(string: "https://test.pipedrive.com/deal/100")!))
    }

    /// Mêmes alertes et même ordre que l'app : en retard et du jour d'abord, par score ; complété par les alertes
    /// à venir s'il en manque.
    func testSnapshotFollowsTheAppOrder() async throws {
        let mock = transport()
        let loader = WidgetFeedLoader(client: PipedriveClient(configuration: config, transport: mock))
        let snapshot = try await loader.load(ownerID: nil, limit: 8, timeZone: paris, now: seventhNoon)
        XCTAssertEqual(snapshot.alerts.map(\.id), [2, 1, 3, 4])
        XCTAssertEqual(snapshot.dueCount, 3, "l'alerte du 20/11 n'est pas en retard")
        let first = snapshot.alerts[0]
        XCTAssertEqual(first.company, "Entreprise Gamma")
        XCTAssertEqual(first.person, "Bruno Test")
        XCTAssertEqual(first.scoreText, "87")
        XCTAssertEqual(first.link, YCRMLink.alert(id: 2), "toucher l'alerte ouvre YCRM, pas Pipedrive")
        XCTAssertEqual(first.dealID, 101)
        XCTAssertEqual(first.personID, 201)
        XCTAssertEqual(first.orgID, 302)
        XCTAssertEqual(snapshot.alerts[1].scoreText, "42,5")
        XCTAssertNil(snapshot.alerts[2].scoreText)
        XCTAssertEqual(snapshot.updatedText(timeZone: paris), "Mis à jour à 13:00")
        let paths = await mock.recorded.compactMap { $0.url?.path }
        XCTAssertEqual(paths.filter { $0 == "/api/v1/users/me" }.count, 1)
        XCTAssertEqual(paths.filter { $0 == "/api/v2/activities" }.count, 2, "moins de 8 alertes du jour : à venir aussi")

        // Assez d'alertes jusqu'à aujourd'hui : rien de plus n'est lu.
        let short = WidgetFeedLoader(client: PipedriveClient(configuration: config, transport: transport()))
        let three = try await short.load(ownerID: 7, limit: 2, timeZone: paris, now: seventhNoon)
        XCTAssertEqual(three.alerts.map(\.id), [2, 1])
        XCTAssertEqual(three.dueCount, 3)
    }

    func testShortDatesAndStatus() {
        func alert(_ day: String?, _ time: String?) -> WidgetAlert {
            WidgetAlert(id: 1, company: "Entreprise Alpha", person: nil, text: "Relancer", score: nil, dueDate: day,
                        dueTime: time, dealID: 100, personID: nil, orgID: nil)
        }
        // 07/11/2026 à 13:00 (Paris).
        XCTAssertEqual(alert("2026-11-07", "13:30").shortDate(now: seventhNoon, timeZone: paris), "14:30")
        XCTAssertEqual(alert("2026-11-07", "13:30").status(now: seventhNoon, timeZone: paris), .today)
        XCTAssertEqual(alert("2026-11-07", nil).shortDate(now: seventhNoon, timeZone: paris), "Aujourd'hui")
        XCTAssertEqual(alert("2026-11-07", "").shortDate(now: seventhNoon, timeZone: paris), "Aujourd'hui")
        XCTAssertEqual(alert("2026-11-01", nil).shortDate(now: seventhNoon, timeZone: paris), "1er nov.")
        XCTAssertEqual(alert("2026-11-01", nil).status(now: seventhNoon, timeZone: paris), .overdue)
        XCTAssertEqual(alert("2026-12-02", "09:00").shortDate(now: seventhNoon, timeZone: paris), "2 déc.")
        XCTAssertEqual(alert("2026-12-02", "09:00").status(now: seventhNoon, timeZone: paris), .upcoming)
        XCTAssertEqual(alert("2025-02-14", nil).shortDate(now: seventhNoon, timeZone: paris), "14 févr. 2025")
        // 06/11 à 23:30 UTC = 07/11 à 00:30 à Paris : aujourd'hui.
        XCTAssertEqual(alert("2026-11-06", "23:30").shortDate(now: seventhNoon, timeZone: paris), "00:30")
        XCTAssertEqual(alert(nil, nil).shortDate(now: seventhNoon, timeZone: paris), "Sans date")
    }

    func testSnapshotIsStoredAndReadBack() throws {
        let snapshot = WidgetSnapshot(alerts: [
            WidgetAlert(id: 1, company: "Entreprise Alpha", person: "Alice Test", text: "Relancer pour le devis",
                        score: 62.5, dueDate: "2026-11-07", dueTime: nil, dealID: 100, personID: 200, orgID: 300),
        ], dueCount: 12, updatedAt: seventhNoon)
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: data), snapshot)
    }
}
