import XCTest
@testable import PipedriveKit

final class HighlightTests: XCTestCase {
    func words(_ text: String) -> [String] {
        KeywordHighlight.ranges(in: text).map { String(text[$0]) }
    }

    func testSignerAndContrat() {
        XCTAssertEqual(words("Relancer pour signer le contrat"), ["signer", "contrat"])
        XCTAssertEqual(words("Devis signé, contrats envoyés, ils signeront lundi"), ["Devis", "signé", "contrats", "signeront"])
        XCTAssertEqual(words("SIGNATURE du Contrat"), ["SIGNATURE", "Contrat"])
        XCTAssertEqual(words("Envoyer le devis puis Devis signé"), ["devis", "Devis", "signé"])
        XCTAssertEqual(words("Ils signent ; elle a signée ; nous signons"), ["signent", "signée", "signons"])
    }

    func testAllFormsOfSignerAndContrat() {
        XCTAssertEqual(words("Relancer pour resigner le contrat, re-signature et contresigné"),
                       ["resigner", "contrat", "re-signature", "contresigné"])
        XCTAssertEqual(words("Avenant et bon de commande à signer"), ["Avenant", "bon de commande", "signer"])
        XCTAssertEqual(words("e-signature du contrat SEO"), ["e-signature", "contrat SEO"])
    }

    func testAccess() {
        XCTAssertEqual(words("Relance accès Google Ads"), ["accès Google Ads"])
        XCTAssertEqual(words("Demander les acces GA4 / GTM"), ["acces GA4 / GTM"])
        XCTAssertEqual(words("accès au compte Google Ads"), ["accès au compte Google Ads"])
    }

    func testTradeWordsAfterKeyword() {
        XCTAssertEqual(words("Envoyer devis audit sécu"), ["devis audit sécu"])
        XCTAssertEqual(words("devis SEO et SEA à relancer"), ["devis SEO et SEA"])
        XCTAssertEqual(words("Signature GEO lundi"), ["Signature GEO"])
        XCTAssertEqual(words("devis d'audit SEO"), ["devis d'audit SEO"])
        XCTAssertEqual(words("devis pour le site web à envoyer"), ["devis pour le site web"])
        XCTAssertEqual(words("Propale SEA + SMA envoyée, signataire : DG"), ["Propale SEA + SMA", "signataire"])
        XCTAssertEqual(words("Devis de montée de version + alors on lance"), ["Devis de montée de version"])
        XCTAssertEqual(words("devis refonte ou montée de version pas avant mars"), ["devis refonte ou montée de version"])
        XCTAssertEqual(words("acces GA + G ADS + FB // relancer"), ["acces GA + G ADS + FB"])
        XCTAssertEqual(words("devis CRO one shot car budget serré"), ["devis CRO one shot"])
        XCTAssertEqual(words("signer tracking SS + attribution + relancer"), ["signer tracking SS + attribution"])
        XCTAssertEqual(words("devis SEO à la perf > relance"), ["devis SEO à la perf"])
        XCTAssertEqual(words("devis secu + devis beug // reparler CRO"), ["devis secu", "devis beug"])
        XCTAssertEqual(words("devis correctifs et maquettes à valider"), ["devis correctifs et maquettes"])
        // Jamais d'une ligne à l'autre.
        XCTAssertEqual(words("devis\nSEO"), ["devis"])
    }

    func testNoFalsePositives() {
        XCTAssertEqual(words("Signaler un signal significatif, contraste, contracter"), [])
        XCTAssertEqual(words("site accessible, designer, assigner, consigne"), [])
        XCTAssertEqual(words(""), [])
    }
}
