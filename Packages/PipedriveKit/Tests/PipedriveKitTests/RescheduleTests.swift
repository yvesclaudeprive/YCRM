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

/// Étiquette « RDV à venir » (demande d'Yves du 09/11/2026) : Google Agenda via l'analyse, ou activité Pipedrive.
final class UpcomingMeetingTests: XCTestCase {
    /// Lundi 09/11/2026 à 10:00, heure de Paris.
    let now = Date(timeIntervalSince1970: 1_794_214_800)

    func testMeetingFromAnalysis() throws {
        let text = "DEVIS ENVOYÉS\n• Refonte | 16/10/2026 | relancé\nRDV À VENIR\n" +
            "• call ALPHA / AGENCE - Cadrage | 12/11/2026 à 14:00 | avec Marie\n" +
            "• Point passé | 02/11/2026 à 10h00 | déjà eu\nAnalyse Claude du 09/11/2026 à 05:17"
        let analysis = try XCTUnwrap(QuoteAnalysis(text: text))
        XCTAssertEqual(analysis.entries(.meeting).count, 2)
        XCTAssertEqual(analysis.entries(.meeting).first?.time, "14:00")
        XCTAssertEqual(analysis.entries(.meeting).last?.time, "10:00", "« 10h00 » est lu aussi")
        let tags = LeadTags(analysis: analysis, firstCallToDo: false, now: now, timeZone: paris)
        XCTAssertTrue(tags.hasUpcomingMeeting)
        XCTAssertEqual(tags.meetings.count, 1, "le rendez-vous passé ne compte pas")
        XCTAssertEqual(tags.meetingLine(now: now, timeZone: paris)?.text, "RDV à venir - jeu. 12 novembre à 14:00 - dans 3j")
        XCTAssertTrue(TagFilter.meeting.matches(tags))
        XCTAssertTrue(tags.hasPendingQuote, "les devis restent affichés")
        XCTAssertFalse(tags.isEmpty)
    }

    func testMeetingFromPipedriveActivity() {
        let meeting = Activity(id: 5, subject: "Visio cadrage", type: "google_agenda", dueDate: "2026-11-10", dueTime: "08:30",
                               dealID: 100, personID: 200, orgID: nil, done: false)
        let task = Activity(id: 6, subject: "Relancer", type: "task", dueDate: "2026-11-10", dueTime: nil,
                            dealID: 100, personID: 200, orgID: nil, done: false)
        let custom = Activity(id: 7, subject: "Point", type: "rdv_client", dueDate: "2026-11-20", dueTime: nil,
                              dealID: 100, personID: 200, orgID: nil, done: false)
        let found = UpcomingMeeting(activity: meeting, typeNames: [:], timeZone: paris)
        XCTAssertEqual(found?.time, "09:30", "heure de Paris")
        XCTAssertNil(UpcomingMeeting(activity: task, typeNames: ["task": "Tâche"], timeZone: paris))
        XCTAssertNotNil(UpcomingMeeting(activity: custom, typeNames: ["rdv_client": "RDV client"], timeZone: paris))
        let tags = LeadTags.none.adding(meetings: [found!], now: now, timeZone: paris)
        XCTAssertEqual(tags.meetingLine(now: now, timeZone: paris)?.text, "RDV à venir - mar. 10 novembre à 09:30 - demain")
    }

    func testUpcomingSortsDeduplicatesAndDropsPast() {
        let a = UpcomingMeeting(title: "A", day: "2026-11-12", time: "14:00", source: .calendar)
        let b = UpcomingMeeting(title: "B", day: "2026-11-12", time: "14:00", source: .pipedrive)
        let c = UpcomingMeeting(title: "C", day: "2026-11-10", time: nil, source: .pipedrive)
        let past = UpcomingMeeting(title: "D", day: "2026-11-09", time: "08:00", source: .calendar)
        let today = UpcomingMeeting(title: "E", day: "2026-11-09", time: nil, source: .pipedrive)
        let upcoming = UpcomingMeeting.upcoming([a, b, c, past, today], now: now, timeZone: paris)
        XCTAssertEqual(upcoming.map(\.day), ["2026-11-09", "2026-11-10", "2026-11-12"], "A et B : un seul (même heure)")
        XCTAssertEqual(upcoming.prefix(2).map(\.title), ["E", "C"])
        XCTAssertEqual(today.countdown(now: now, timeZone: paris), "auj.")
    }

    /// Toucher « RDV à venir » ouvre Google Agenda (demande d'Yves du 09/11/2026) : l'événement si l'analyse a noté
    /// son lien, sinon la journée du rendez-vous (lien fictif).
    func testCalendarLink() throws {
        let text = "RDV À VENIR\n" +
            "• call ALPHA | 12/11/2026 à 14:00 | avec Marie | https://www.google.com/calendar/event?eid=QUJDMTIz\n" +
            "• Point | 20/11/2026 | sans lien\nAnalyse Claude du 09/11/2026 à 05:17"
        let analysis = try XCTUnwrap(QuoteAnalysis(text: text))
        let alpha = try XCTUnwrap(analysis.entries(.meeting).first { $0.title == "call ALPHA" })
        XCTAssertEqual(alpha.detail, "avec Marie", "le lien n'apparaît pas dans le détail")
        XCTAssertEqual(alpha.link, "https://www.google.com/calendar/event?eid=QUJDMTIz")
        XCTAssertEqual(alpha.time, "14:00")
        XCTAssertNil(analysis.entries(.meeting).first { $0.title == "Point" }?.link)
        let tags = LeadTags(analysis: analysis, firstCallToDo: false, now: now, timeZone: paris)
        XCTAssertEqual(tags.nextMeeting(now: now, timeZone: paris)?.calendarURL?.absoluteString,
                       "https://calendar.google.com/calendar/event?eid=QUJDMTIz", "lien universel calendar.google.com")

        let bare = QuoteAnalysis.entry("call B | 13/11/2026 à 09:00 | https://calendar.google.com/calendar/event?eid=WFla",
                                       status: .meeting)
        XCTAssertNil(bare.detail)
        XCTAssertEqual(bare.link, "https://calendar.google.com/calendar/event?eid=WFla")

        let pipedrive = UpcomingMeeting(title: "Visio", day: "2026-11-20", time: nil, source: .pipedrive)
        XCTAssertEqual(pipedrive.calendarURL?.absoluteString, "https://calendar.google.com/calendar/r/day/2026/11/20",
                       "sans lien : la journée du rendez-vous")
        let foreign = UpcomingMeeting(title: "X", day: "2027-01-04", time: nil, source: .calendar,
                                      link: "https://google.com.example.org/calendar/event?eid=AAA")
        XCTAssertEqual(foreign.calendarURL?.absoluteString, "https://calendar.google.com/calendar/r/day/2027/1/4",
                       "un lien qui n'est pas Google Agenda n'est jamais ouvert")
    }

    func testSameMeetingKeepsTheCalendarLink() {
        let pipedrive = UpcomingMeeting(title: "Visio", day: "2026-11-12", time: "14:00", source: .pipedrive)
        let calendar = UpcomingMeeting(title: "call ALPHA", day: "2026-11-12", time: "14:00", source: .calendar,
                                       link: "https://www.google.com/calendar/event?eid=QUJD")
        let upcoming = UpcomingMeeting.upcoming([pipedrive, calendar], now: now, timeZone: paris)
        XCTAssertEqual(upcoming.count, 1)
        XCTAssertEqual(upcoming.first?.link, "https://www.google.com/calendar/event?eid=QUJD")
    }
}

/// Champ d'analyse avec seulement des rendez-vous ou des accès : l'app cherche quand même les devis elle-même.
final class PartialAnalysisTests: XCTestCase {
    func testCoversQuotes() throws {
        let meetingsOnly = try XCTUnwrap(QuoteAnalysis(text: "RDV À VENIR\n• call X | 12/11/2026 à 10:00 | avec Y\nAnalyse Claude du 09/11/2026 à 01:56"))
        XCTAssertFalse(meetingsOnly.coversQuotes)
        let accessOnly = try XCTUnwrap(QuoteAnalysis(text: "ACCÈS EN ATTENTE\n• FTP | 02/07/2026 | demandé\nAnalyse Claude du 09/11/2026 à 01:56"))
        XCTAssertFalse(accessOnly.coversQuotes)
        let none = try XCTUnwrap(QuoteAnalysis(text: "AUCUN DEVIS\nAnalyse Claude du 09/11/2026 à 01:56"))
        XCTAssertTrue(none.coversQuotes)
        XCTAssertTrue(none.entries.isEmpty)
        let quotes = try XCTUnwrap(QuoteAnalysis(text: "DEVIS ENVOYÉS\n• Refonte | 16/10/2026 | relancé\nAnalyse Claude du 09/11/2026 à 01:56"))
        XCTAssertTrue(quotes.coversQuotes)
    }

    func testAddingAccessAndMeetingsKeepsLocalQuotes() {
        let local = LeadTags(quoteSentDay: "2026-11-02", firstCallToDo: true)
        let meeting = UpcomingMeeting(title: "call X", day: "2026-11-12", time: "10:00", source: .calendar)
        let access = QuoteSent(id: 0, source: .analysis, subject: "FTP", day: "2026-07-02", dateText: "2 juillet", note: nil)
        let now = Date(timeIntervalSince1970: 1_794_214_800)
        let merged = local.adding(access: [access], meetings: [meeting], now: now, timeZone: paris)
        XCTAssertTrue(merged.hasPendingQuote)
        XCTAssertTrue(merged.firstCallToDo)
        XCTAssertTrue(merged.hasAccessPending)
        XCTAssertTrue(merged.hasUpcomingMeeting)
    }
}
