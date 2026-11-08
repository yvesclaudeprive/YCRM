import XCTest
@testable import PipedriveKit

final class FormatTests: XCTestCase {
    let nnbsp = FrenchFormat.thousandsSeparator

    func testNumbers() {
        XCTAssertEqual(FrenchFormat.integer(7356), "7\(nnbsp)356")
        XCTAssertEqual(FrenchFormat.integer(1234567), "1\(nnbsp)234\(nnbsp)567")
        XCTAssertEqual(FrenchFormat.integer(12), "12")
        XCTAssertEqual(FrenchFormat.number(1600.5), "1\(nnbsp)600,5")
        XCTAssertEqual(FrenchFormat.number(0.1), "0,1")
        XCTAssertEqual(FrenchFormat.number(-2.456), "-2,46")
        XCTAssertEqual(FrenchFormat.number(9.999), "10")
    }

    func testMoney() {
        XCTAssertEqual(FrenchFormat.money(7356, currency: "EUR"), "7\(nnbsp)356,00\u{00A0}€")
        XCTAssertEqual(FrenchFormat.money(5, currency: "XYZ"), "5,00\u{00A0}XYZ")
    }

    func testParseNumber() {
        XCTAssertEqual(FrenchFormat.parseNumber("1 600,50"), 1600.5)
        XCTAssertEqual(FrenchFormat.parseNumber("1600.5"), 1600.5)
        XCTAssertEqual(FrenchFormat.parseNumber("7\u{202F}356 €"), 7356)
        XCTAssertNil(FrenchFormat.parseNumber("abc"))
        XCTAssertNil(FrenchFormat.parseNumber(""))
    }

    func testDates() throws {
        XCTAssertEqual(FrenchFormat.date(fromAPI: "2026-07-08"), "08/07/2026")
        // 14:12 UTC = 15:12 à Paris en décembre
        XCTAssertEqual(FrenchFormat.date(fromAPI: "2025-12-01T14:12:54Z"), "01/12/2025 à 15:12")
        // Minuit à Paris : heure omise
        XCTAssertEqual(FrenchFormat.date(fromAPI: "2026-06-30T22:00:00Z"), "01/07/2026")

        let paris = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let date = try XCTUnwrap(FrenchFormat.date(fromAPIDay: "2026-07-08", timeZone: paris))
        XCTAssertEqual(FrenchFormat.apiDay(from: date, timeZone: paris), "2026-07-08")
        XCTAssertNil(FrenchFormat.date(fromAPIDay: "pas une date"))
    }

    func testLongDate() {
        let now = Date(timeIntervalSince1970: 1_794_056_000) // 07/11/2026
        XCTAssertEqual(FrenchFormat.longDate(fromAPI: "2026-11-02", now: now), "2 novembre")
        XCTAssertEqual(FrenchFormat.longDate(fromAPI: "2026-03-01", now: now), "1er mars")
        XCTAssertEqual(FrenchFormat.longDate(fromAPI: "2025-12-12", now: now), "12 décembre 2025")
        XCTAssertEqual(FrenchFormat.longDate(fromAPI: "2026-08-15T12:30:00Z", now: now), "15 août à 14:30")
        XCTAssertEqual(FrenchFormat.longDate(fromAPI: "2026-06-30T22:00:00Z", now: now), "1er juillet", "minuit : heure omise")
        XCTAssertEqual(FrenchFormat.longDate(fromAPI: "n'importe quoi", now: now), "n'importe quoi")
    }

    func testDomainValidation() {
        XCTAssertTrue(PipedriveConfiguration.isValidDomain("exemple"))
        XCTAssertTrue(PipedriveConfiguration.isValidDomain(" Mon-Entreprise2 "))
        XCTAssertFalse(PipedriveConfiguration.isValidDomain("exemple.pipedrive.com"))
        XCTAssertFalse(PipedriveConfiguration.isValidDomain("evil.com/x"))
        XCTAssertFalse(PipedriveConfiguration.isValidDomain(""))
        XCTAssertFalse(PipedriveConfiguration.isValidDomain("-yateo"))
    }
}
