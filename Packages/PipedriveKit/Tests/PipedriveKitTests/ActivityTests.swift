import XCTest
@testable import PipedriveKit

final class ActivityTests: XCTestCase {
    func activities() throws -> [Activity] {
        try (decode(Fixtures.activities)["data"].arrayValue ?? []).compactMap(Activity.init(json:))
    }

    func testDecoding() throws {
        let list = try activities()
        XCTAssertEqual(list.count, 4)
        XCTAssertEqual(list[1].personID, 201, "personne principale prise dans participants")
        XCTAssertEqual(list[1].dueTime, "23:30")
        XCTAssertNil(list[2].dueTime, "heure vide = pas d'heure")
    }

    func testLocalDayAndDisplay() throws {
        let now = Date(timeIntervalSince1970: 1_794_056_000) // 07/11/2026
        let late = try activities()[1] // 06/11 à 23:30 UTC = 07/11 à 00:30 à Paris
        XCTAssertEqual(late.localDay(timeZone: paris), "2026-11-07")
        XCTAssertEqual(late.displayDate(now: now), "7 novembre à 00:30")
        XCTAssertEqual(try activities()[0].displayDate(now: now), "1er novembre")
        let nextYear = now.addingTimeInterval(400 * 86_400)
        XCTAssertEqual(try activities()[0].displayDate(now: nextYear), "1er novembre 2026", "année affichée si différente")
    }

    func testDateFilter() {
        let filter = ActivityDateFilter.untilToday(now: Date(timeIntervalSince1970: 1_794_056_000), timeZone: paris)
        XCTAssertEqual(filter.to, "2026-11-07")
        XCTAssertTrue(filter.contains(day: "2026-11-07"))
        XCTAssertTrue(filter.contains(day: "2025-01-01"))
        XCTAssertFalse(filter.contains(day: "2026-11-08"))
        let now = Date(timeIntervalSince1970: 1_794_056_000)
        XCTAssertEqual(filter.label(now: now), "Jusqu'au 7 novembre")
        XCTAssertEqual(ActivityDateFilter(from: nil, to: nil).label, "Toutes les dates")
        XCTAssertEqual(ActivityDateFilter(from: "2026-11-07", to: "2026-11-07").label(now: now), "Le 7 novembre")
        XCTAssertEqual(ActivityDateFilter(from: "2025-12-12", to: "2026-01-03").label(now: now), "Du 12 décembre 2025 au 3 janvier")
        XCTAssertFalse(ActivityDateFilter(from: "2026-11-01", to: nil).contains(day: "2026-10-31"))
    }

    func testDatePresets() throws {
        let now = Date(timeIntervalSince1970: 1_794_056_000) // 07/11/2026 à Paris
        XCTAssertEqual(DatePreset.untilToday.filter(now: now, timeZone: paris), ActivityDateFilter(from: nil, to: "2026-11-07"))
        XCTAssertEqual(DatePreset.today.filter(now: now, timeZone: paris), ActivityDateFilter(from: "2026-11-07", to: "2026-11-07"))
        XCTAssertEqual(DatePreset.overdue.filter(now: now, timeZone: paris), ActivityDateFilter(from: nil, to: "2026-11-06"))
        XCTAssertEqual(DatePreset.upcoming.filter(now: now, timeZone: paris), ActivityDateFilter(from: "2026-11-08", to: nil))
        XCTAssertEqual(DatePreset.next7Days.filter(now: now, timeZone: paris), ActivityDateFilter(from: "2026-11-07", to: "2026-11-14"))
        XCTAssertEqual(DatePreset.all.filter(now: now, timeZone: paris), ActivityDateFilter(from: nil, to: nil))
        let later = now.addingTimeInterval(10 * 86_400)
        XCTAssertEqual(DatePreset.custom.filter(now: now, timeZone: paris, customFrom: later, customTo: now),
                       ActivityDateFilter(from: "2026-11-07", to: "2026-11-17"), "bornes inversées remises dans l'ordre")
    }

    func testDateStatus() {
        let now = Date(timeIntervalSince1970: 1_794_056_000) // 07/11/2026 à Paris
        func status(_ day: String, _ time: String? = nil) -> DateStatus? {
            Activity(id: 1, subject: "", type: "task", dueDate: day, dueTime: time, dealID: nil, personID: nil,
                     orgID: nil, done: false).dateStatus(now: now, timeZone: paris)
        }
        XCTAssertEqual(status("2026-11-06"), .overdue)
        XCTAssertEqual(status("2026-11-07"), .today)
        XCTAssertEqual(status("2026-11-06", "23:30"), .today, "23:30 UTC le 06 = 00:30 à Paris le 07")
        XCTAssertEqual(status("2026-11-08"), .upcoming)
    }

    func testScoreBands() {
        XCTAssertEqual(ScoreBand(score: 0), .veryLow)
        XCTAssertEqual(ScoreBand(score: 19.9), .veryLow)
        XCTAssertEqual(ScoreBand(score: 20), .low)
        XCTAssertEqual(ScoreBand(score: 45), .medium)
        XCTAssertEqual(ScoreBand(score: 75), .high)
        XCTAssertEqual(ScoreBand(score: 80), .veryHigh)
        XCTAssertEqual(ScoreBand(score: 120), .veryHigh)
    }

    func testPrioritySort() {
        func item(_ id: Int, score: Double?, day: String, time: String? = nil) -> ActivityItem {
            let activity = Activity(id: id, subject: "", type: "task", dueDate: day, dueTime: time,
                                    dealID: score == nil ? nil : id, personID: nil, orgID: nil, done: false)
            let deal = score.map { DealSummary(id: id, title: "", orgID: nil, personID: nil, score: $0) }
            return ActivityItem(activity: activity, organizationName: nil, person: nil, deal: deal)
        }
        let sorted = [
            item(1, score: nil, day: "2026-01-01"),
            item(2, score: 10, day: "2026-11-01"),
            item(3, score: 90, day: "2026-11-05"),
            item(4, score: 10, day: "2026-10-01"),
            item(5, score: nil, day: "2025-12-31"),
        ].sorted(by: ActivityItem.prioritySort)
        XCTAssertEqual(sorted.map(\.id), [3, 4, 2, 5, 1])
    }

    func testActivityTypeByName() throws {
        let types = try (decode(Fixtures.activityTypes)["data"].arrayValue ?? []).compactMap(ActivityType.init(json:))
        XCTAssertEqual(ActivityType.named("Répondeur ON/OFF", in: types)?.key, "rpondeur_onoff")
        XCTAssertEqual(ActivityType.named("repondeur  sans MESSAGE", in: types)?.key, "rpondeur_sans_message")
        XCTAssertNil(ActivityType.named("Inconnu", in: types))
    }

    func testSearchAndSelfMail() {
        let activity = Activity(id: 1, subject: "Relancer le devis", type: "task", dueDate: "2026-11-01", dueTime: nil,
                                dealID: nil, personID: 1, orgID: 1, done: false)
        let person = PersonContact(id: 1, name: "Élodie Test", phones: [], emails: [], orgID: 1)
        let item = ActivityItem(activity: activity, organizationName: "Société Test", person: person, deal: nil)
        XCTAssertTrue(item.matches(search: "elodie devis"))
        XCTAssertTrue(item.matches(search: "  "))
        XCTAssertFalse(item.matches(search: "facture"))
        XCTAssertEqual(item.selfMailSubject, "[SOCIÉTÉ TEST] Relancer le devis")
    }

    func testPersonContactPointsPrimaryFirstAndDeduplicated() throws {
        let persons = try (decode(Fixtures.persons)["data"].arrayValue ?? []).compactMap(PersonContact.init(json:))
        XCTAssertEqual(persons[0].phones.map(\.value), ["06 11 22 33 44", "01 23 45 67 89"])
        XCTAssertEqual(persons[2].emails.count, 1, "même adresse en majuscules = doublon")
    }
}
