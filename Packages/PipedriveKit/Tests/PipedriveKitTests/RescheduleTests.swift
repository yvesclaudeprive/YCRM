import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PipedriveKit

/// Bouton « Décaler » : choix rapides, conversion de l'heure de Paris vers l'UTC de Pipedrive (données fictives).
final class RescheduleTests: XCTestCase {
    /// Lundi 09/11/2026 à 10:00, heure de Paris.
    let monday = Date(timeIntervalSince1970: 1_794_214_800)
    /// Vendredi 13/11/2026 à 10:00, heure de Paris.
    let friday = Date(timeIntervalSince1970: 1_794_560_400)

    func testChoicesOnAMonday() {
        let choices = Reschedule.choices(now: monday, timeZone: paris)
        XCTAssertEqual(choices.map(\.title), ["Demain", "Après-demain", "Vendredi", "Lundi prochain", "Dans 2 semaines",
                                              "Début du mois prochain", "Dans un mois", "Après les fêtes", "Dans 3 mois",
                                              "Dans 6 mois"],
                       "« Dans une semaine » tombe le même lundi que « Lundi prochain » : une seule fois")
        XCTAssertEqual(choices.map(\.day), ["2026-11-10", "2026-11-11", "2026-11-13", "2026-11-16", "2026-11-23",
                                            "2026-12-01", "2026-12-09", "2027-01-04", "2027-02-09", "2027-05-10"],
                       "le 09/05/2027 est un dimanche : lundi 10/05/2027")
        XCTAssertEqual(choices.first?.dateText, "mar. 10 novembre")
        XCTAssertEqual(choices.first { $0.title == "Après les fêtes" }?.dateText, "lun. 4 janvier 2027")
    }

    func testChoicesOnAFridaySkipTheWeekend() {
        let choices = Reschedule.choices(now: friday, timeZone: paris)
        XCTAssertEqual(choices.first?.title, "Demain")
        XCTAssertEqual(choices.first?.day, "2026-11-16", "demain samedi : lundi")
        XCTAssertFalse(choices.contains { $0.title == "Vendredi" })
        XCTAssertFalse(choices.contains { $0.title == "Lundi prochain" }, "même jour que « Demain »")
        XCTAssertEqual(choices.first { $0.title == "Dans une semaine" }?.day, "2026-11-20")
        XCTAssertEqual(choices.first { $0.title == "Dans un mois" }?.day, "2026-12-14", "13/12 est un dimanche")
        for choice in choices {
            let date = FrenchFormat.date(fromAPIDay: choice.day, timeZone: paris)!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = paris
            XCTAssertFalse([1, 7].contains(calendar.component(.weekday, from: date)), "\(choice.title) : pas de week-end")
        }
    }

    func testDueKeepsParisTimeInUTC() {
        XCTAssertEqual(Reschedule.due(day: "2026-11-16", parisTime: "14:30", timeZone: paris).date, "2026-11-16")
        XCTAssertEqual(Reschedule.due(day: "2026-11-16", parisTime: "14:30", timeZone: paris).time, "13:30")
        XCTAssertEqual(Reschedule.due(day: "2027-05-10", parisTime: "09:00", timeZone: paris).time, "07:00", "heure d'été")
        let midnight = Reschedule.due(day: "2026-11-16", parisTime: "00:30", timeZone: paris)
        XCTAssertEqual(midnight.date, "2026-11-15")
        XCTAssertEqual(midnight.time, "23:30")
        let allDay = Reschedule.due(day: "2026-11-16", parisTime: nil, timeZone: paris)
        XCTAssertEqual(allDay.date, "2026-11-16")
        XCTAssertNil(allDay.time)
    }

    func testParisTimeAndWithDue() {
        let activity = Activity(id: 1, subject: "Relancer", type: "task", dueDate: "2026-11-09", dueTime: "13:30",
                                dealID: 100, personID: 200, orgID: 300, done: false, ownerID: 7)
        XCTAssertEqual(Reschedule.parisTime(of: activity, timeZone: paris), "14:30")
        let moved = activity.withDue(date: "2026-11-16", time: "13:30")
        XCTAssertEqual(moved.localDay(timeZone: paris), "2026-11-16")
        XCTAssertEqual(moved.id, activity.id)
        XCTAssertEqual(moved.ownerID, 7)
        XCTAssertNil(Reschedule.parisTime(of: activity.withDue(date: "2026-11-16", time: nil), timeZone: paris))
    }

    func testRescheduleSendsPatch() async throws {
        let transport = MockTransport([
            "PATCH /api/v2/activities/42": .init(status: 200, body: #"{"success":true,"data":{"id":42}}"#),
        ])
        let client = PipedriveClient(configuration: .init(companyDomain: "test", apiToken: "t"), transport: transport)
        try await client.rescheduleActivity(id: 42, dueDate: "2026-11-16", dueTime: "13:30")
        try await client.rescheduleActivity(id: 42, dueDate: "2026-11-17", dueTime: nil)
        let recorded = await transport.recorded
        XCTAssertEqual(recorded.first?.httpMethod, "PATCH")
        let first = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(recorded.first?.httpBody))
        XCTAssertEqual(first["due_date"].stringValue, "2026-11-16")
        XCTAssertEqual(first["due_time"].stringValue, "13:30")
        let second = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(recorded.last?.httpBody))
        XCTAssertEqual(second["due_date"].stringValue, "2026-11-17")
        XCTAssertTrue(second["due_time"].isNull, "sans heure : l'heure est effacée")
    }
}
