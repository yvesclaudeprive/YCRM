import XCTest
@testable import PipedriveKit

final class PhoneAndLinksTests: XCTestCase {
    func testE164() {
        XCTAssertEqual(PhoneNumber.e164("06 11 22 33 44"), "+33611223344")
        XCTAssertEqual(PhoneNumber.e164("06.11.22.33.44"), "+33611223344")
        XCTAssertEqual(PhoneNumber.e164("+33 (0)6 11 22 33 44"), "+33611223344")
        XCTAssertEqual(PhoneNumber.e164("0033 6 11 22 33 44"), "+33611223344")
        XCTAssertEqual(PhoneNumber.e164("+44 20 7946 0958"), "+442079460958")
        XCTAssertEqual(PhoneNumber.e164("611223344"), "+33611223344")
        XCTAssertNil(PhoneNumber.e164("abc"))
        XCTAssertNil(PhoneNumber.e164("1234"))
    }

    func testMobileAndDisplay() {
        XCTAssertTrue(PhoneNumber.isLikelyMobile("+33611223344"))
        XCTAssertTrue(PhoneNumber.isLikelyMobile("+33711223344"))
        XCTAssertFalse(PhoneNumber.isLikelyMobile("+33123456789"))
        XCTAssertTrue(PhoneNumber.isLikelyMobile("+442079460958"), "étranger : inconnu, on propose WhatsApp")
        XCTAssertEqual(PhoneNumber.display("+33611223344"), "+33 6 11 22 33 44")
        XCTAssertEqual(PhoneNumber.display("+442079460958"), "+442079460958")
    }

    func testCallLinks() {
        XCTAssertEqual(ActionLinks.phoneCall("+33611223344")?.absoluteString, "tel:+33611223344")
        XCTAssertEqual(ActionLinks.aircall("+33611223344")?.absoluteString, "aircall://call?to=+33611223344")
        XCTAssertEqual(ActionLinks.whatsapp("+33611223344")?.absoluteString, "https://wa.me/33611223344")
        XCTAssertEqual(ActionLinks.onoff("+33611223344", template: ActionLinks.defaultOnOffTemplate)?.absoluteString,
                       "onoff://call?number=+33611223344")
        XCTAssertEqual(ActionLinks.onoff("+33611223344", template: "onoff://dial/{numero_sans_plus}")?.absoluteString,
                       "onoff://dial/33611223344")
    }

    func testSmsShortcutAndScheme() {
        XCTAssertEqual(ActionLinks.sms("+33611223344")?.absoluteString, "sms:+33611223344")
        XCTAssertEqual(ActionLinks.shortcut(named: "YCRM OnOff", text: "+33611223344")?.absoluteString,
                       "shortcuts://run-shortcut?name=YCRM%20OnOff&input=text&text=%2B33611223344")
        XCTAssertNil(ActionLinks.shortcut(named: "  ", text: "+33611223344"))
        XCTAssertEqual(ActionLinks.scheme(ofTemplate: "OnOff://call?number={numero}"), "onoff")
        XCTAssertNil(ActionLinks.scheme(ofTemplate: "pas de schéma"))
    }

    func testMailto() {
        let url = ActionLinks.mailto(to: "moi@example.com", subject: "[Société & Fils] Relance ?", body: "https://test.pipedrive.com/deal/9")
        XCTAssertEqual(url?.absoluteString,
                       "mailto:moi@example.com?subject=%5BSoci%C3%A9t%C3%A9%20%26%20Fils%5D%20Relance%20%3F&body=https%3A%2F%2Ftest.pipedrive.com%2Fdeal%2F9")
        XCTAssertEqual(ActionLinks.mailto(to: "client@example.com")?.absoluteString, "mailto:client@example.com")
        XCTAssertNil(ActionLinks.mailto(to: "pas une adresse"))
    }

    func testSuperhumanAndPipedriveLinks() {
        XCTAssertEqual(ActionLinks.superhumanThread(account: "moi@example.com", threadID: "1e00000000000def",
                                                    template: ActionLinks.defaultSuperhumanTemplate)?.absoluteString,
                       "https://mail.superhuman.com/moi@example.com/thread/1e00000000000def")
        XCTAssertEqual(ActionLinks.pipedrive(domain: "test", dealID: 9, personID: 1, orgID: 2)?.absoluteString,
                       "https://test.pipedrive.com/deal/9")
        XCTAssertEqual(ActionLinks.pipedrive(domain: "test", dealID: nil, personID: 1, orgID: 2)?.absoluteString,
                       "https://test.pipedrive.com/person/1")
        XCTAssertNil(ActionLinks.pipedrive(domain: "test", dealID: nil, personID: nil, orgID: nil))
        XCTAssertEqual(ActionLinks.pipedriveOrganization(domain: "test", id: 3)?.absoluteString, "https://test.pipedrive.com/organization/3")
        XCTAssertEqual(ActionLinks.pipedrivePerson(domain: "test", id: 4)?.absoluteString, "https://test.pipedrive.com/person/4")
    }

    func testGmailIDFromStoragePath() {
        XCTAssertEqual(MailHint.gmailID(fromStoragePath: "1-2/abc/1f00000000000abc/body"), "1f00000000000abc")
        XCTAssertEqual(MailHint.gmailID(fromStoragePath: "https://cdn.example.com/x/1E00000000000DEF/body?Expires=1"), "1e00000000000def")
        XCTAssertNil(MailHint.gmailID(fromStoragePath: "?Expires=0"))
        XCTAssertNil(MailHint.gmailID(fromStoragePath: "x/pas-hexa/body"))
        XCTAssertNil(MailHint.gmailID(fromStoragePath: nil))
    }
}
