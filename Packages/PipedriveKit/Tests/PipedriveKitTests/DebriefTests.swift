import XCTest
@testable import PipedriveKit

/// « Debrief call » (demande d'Yves du 13/11/2026) : chaque retour à la ligne crée une puce, des boutons décalent
/// la puce à droite ou à gauche et mettent en gras, et la note Pipedrive reprend le format de son éditeur
/// (titre en gras, `<ul><li>`, sous-liste placée directement dans la liste du dessus, gras en `<b>`).
/// Données fictives.
final class DebriefTests: XCTestCase {
    /// Fenêtre simulée : texte, curseur, et les mêmes réactions que l'app (frappe, touche retour, boutons).
    struct Editor {
        var text = DebriefTemplate.starter
        var selection = DebriefRange(location: DebriefTemplate.starter.utf16.count)

        mutating func type(_ typed: String) {
            apply(DebriefChange(edits: [DebriefEdit(range: selection, replacement: typed)],
                                selection: DebriefRange(location: selection.location + typed.utf16.count)))
        }

        mutating func pressReturn() {
            apply(DebriefEditing.newline(in: text, selection: selection))
        }

        mutating func indent() {
            if let change = DebriefEditing.indent(in: text, selection: selection) { apply(change) }
        }

        mutating func outdent() {
            if let change = DebriefEditing.outdent(in: text, selection: selection) { apply(change) }
        }

        mutating func apply(_ change: DebriefChange) {
            text = change.apply(to: text)
            selection = change.selection
        }

        var html: String { DebriefTemplate.html(from: text) }
    }

    let heading = "Je l'ai eu au téléphone et :"

    func testEachReturnStartsANewBullet() {
        var editor = Editor()
        editor.type("intéressée")
        editor.pressReturn()
        editor.type("a peur de lancer")
        XCTAssertEqual(editor.text, "\(heading)\n• intéressée\n• a peur de lancer")
        XCTAssertEqual(editor.selection, DebriefRange(location: editor.text.utf16.count))
        XCTAssertEqual(editor.html, "\(heading)<ul><li>intéressée</li><li>a peur de lancer</li></ul>")
    }

    /// Le format des notes d'Yves dans Pipedrive : sous-liste `<ul>` directement dans la liste du dessus.
    func testIndentButtonsBuildNestedListsLikePipedrive() {
        var editor = Editor()
        editor.type("Personnes :")
        editor.pressReturn()
        editor.indent()
        editor.type("Camille : directrice marketing")
        editor.pressReturn()
        editor.indent()
        editor.type("porte le sujet")
        editor.pressReturn()
        editor.outdent()
        editor.outdent()
        editor.type("Budget")
        editor.pressReturn()
        editor.indent()
        editor.type("environ 2 000 € / mois")
        XCTAssertEqual(editor.text, "\(heading)\n• Personnes :\n\t◦ Camille : directrice marketing\n\t\t▪ porte le sujet"
                                    + "\n• Budget\n\t◦ environ 2 000 € / mois")
        XCTAssertEqual(editor.html, "\(heading)<ul><li>Personnes :</li><ul><li>Camille : directrice marketing</li>"
                                    + "<ul><li>porte le sujet</li></ul></ul><li>Budget</li>"
                                    + "<ul><li>environ 2 000 € / mois</li></ul></ul>")
    }

    /// Retour sur une puce vide : elle remonte d'un cran, puis redevient une ligne simple (comme dans Notes).
    func testReturnOnEmptyBulletGoesBackOneLevel() {
        var editor = Editor()
        editor.type("point")
        editor.pressReturn()
        editor.indent()
        editor.type("détail")
        editor.pressReturn()
        XCTAssertEqual(editor.text, "\(heading)\n• point\n\t◦ détail\n\t◦ ")
        editor.pressReturn()
        XCTAssertEqual(editor.text, "\(heading)\n• point\n\t◦ détail\n• ")
        editor.pressReturn()
        XCTAssertEqual(editor.text, "\(heading)\n• point\n\t◦ détail\n")
        XCTAssertEqual(editor.selection, DebriefRange(location: editor.text.utf16.count))
        editor.type("Rappeler lundi")
        XCTAssertEqual(editor.html, "\(heading)<ul><li>point</li><ul><li>détail</li></ul></ul><div>Rappeler lundi</div>")
        // Et un retour depuis cette ligne simple redonne une puce.
        editor.pressReturn()
        XCTAssertTrue(editor.text.hasSuffix("Rappeler lundi\n• "))
    }

    func testReturnInsideABulletSplitsIt() {
        var editor = Editor()
        editor.type("devis SEO et SEA")
        editor.selection = DebriefRange(location: DebriefTemplate.starter.utf16.count + "devis SEO".utf16.count)
        editor.pressReturn()
        XCTAssertEqual(editor.text, "\(heading)\n• devis SEO\n• et SEA", "l'espace après le curseur ne passe pas à la ligne")
        editor.type("x ")
        XCTAssertEqual(editor.html, "\(heading)<ul><li>devis SEO</li><li>x et SEA</li></ul>")
    }

    func testReturnBeforeTheBulletTextAddsAnEmptyBulletAbove() {
        var editor = Editor()
        editor.type("point")
        let lineStart = (heading + "\n").utf16.count
        for offset in [0, 1] {
            var copy = editor
            copy.selection = DebriefRange(location: lineStart + offset)
            copy.pressReturn()
            XCTAssertEqual(copy.text, "\(heading)\n• \n• point")
            XCTAssertEqual(copy.selection, DebriefRange(location: lineStart + 5), "curseur devant « point »")
        }
    }

    func testReturnAtTheStartOfTheHeadingKeepsTheHeading() {
        var editor = Editor()
        editor.selection = DebriefRange(location: 0)
        editor.pressReturn()
        XCTAssertEqual(editor.text, "\n\(heading)\n• ")
        XCTAssertEqual(editor.selection, DebriefRange(location: 1))
        XCTAssertEqual(editor.html, heading)
    }

    func testIndentAndOutdentSeveralLines() throws {
        let text = "Titre\n• a\n• b\n\n• c"
        let start = text.utf16.count - "a\n• b\n\n• c".utf16.count
        let selection = DebriefRange(location: start, length: text.utf16.count - start)

        let indented = try XCTUnwrap(DebriefEditing.indent(in: text, selection: selection))
        let text2 = indented.apply(to: text)
        XCTAssertEqual(text2, "Titre\n\t◦ a\n\t◦ b\n\n\t◦ c", "la ligne vide ne bouge pas")
        XCTAssertEqual(indented.selection, DebriefRange(location: 9, length: 12), "la sélection suit le texte")

        let outdented = try XCTUnwrap(DebriefEditing.outdent(in: text2, selection: indented.selection))
        let text3 = outdented.apply(to: text2)
        XCTAssertEqual(text3, "Titre\n• a\n• b\n\n• c")

        let plain = try XCTUnwrap(DebriefEditing.outdent(in: text3, selection: outdented.selection))
        let text4 = plain.apply(to: text3)
        XCTAssertEqual(text4, "Titre\na\nb\n\nc", "au 1er cran, la puce redevient une ligne simple")
        XCTAssertNil(DebriefEditing.outdent(in: text4, selection: plain.selection), "plus rien à décaler")
    }

    func testIndentLimitsAndPlainLines() throws {
        XCTAssertNil(DebriefEditing.outdent(in: "Titre", selection: DebriefRange(location: 2)))
        XCTAssertNil(DebriefEditing.indent(in: "\t\t\t▪ x", selection: DebriefRange(location: 5)),
                     "\(DebriefFormat.maxLevel) crans au plus")
        let change = try XCTUnwrap(DebriefEditing.indent(in: "Titre\nsuite", selection: DebriefRange(location: 8)))
        XCTAssertEqual(change.apply(to: "Titre\nsuite"), "Titre\n• suite", "une ligne simple devient une puce")
        XCTAssertEqual(change.selection, DebriefRange(location: 10), "le curseur reste au même endroit du texte")

        // Curseur au tout début de la ligne : il se place après le nouveau symbole.
        let start = try XCTUnwrap(DebriefEditing.indent(in: "• a", selection: DebriefRange(location: 0)))
        XCTAssertEqual(start.apply(to: "• a"), "\t◦ a")
        XCTAssertEqual(start.selection, DebriefRange(location: 3))

        // Sélection qui s'arrête au début de la ligne suivante : seule la 1re ligne bouge.
        let text = "• a\n• b\n• c"
        let first = try XCTUnwrap(DebriefEditing.indent(in: text, selection: DebriefRange(location: 0, length: 4)))
        XCTAssertEqual(first.apply(to: text), "\t◦ a\n• b\n• c")
    }

    /// Gras : repris en `<b>` dans Pipedrive, comme dans les notes d'Yves.
    func testBoldIsKeptInThePipedriveNote() {
        let runs = [
            DebriefRun(heading, bold: true), DebriefRun("\n• "), DebriefRun("Personnes :", bold: true),
            DebriefRun("\n\t◦ "), DebriefRun("Camille", bold: true), DebriefRun(" : directrice "),
            DebriefRun("marketing", bold: true), DebriefRun("\n• vu le "), DebriefRun("budget", bold: true), DebriefRun(" "),
        ]
        XCTAssertEqual(DebriefTemplate.html(from: runs),
                       "<b>\(heading)</b><ul><li><b>Personnes :</b></li><ul><li><b>Camille</b> : directrice "
                       + "<b>marketing</b></li></ul><li>vu le <b>budget</b></li></ul>")
        XCTAssertEqual(DebriefTemplate.html(from: DebriefTemplate.starterRuns), "<b>\(heading)</b>",
                       "puce vide du modèle retirée")
    }

    func testBoldOnSymbolsAndSpacesIsIgnored() {
        XCTAssertEqual(DebriefTemplate.html(from: [DebriefRun("• Budget  ", bold: true)]), "<ul><li><b>Budget</b></li></ul>")
        XCTAssertEqual(DebriefTemplate.html(from: [DebriefRun("• "), DebriefRun("Budget", bold: true),
                                                   DebriefRun(" ", bold: true), DebriefRun("ok")]),
                       "<ul><li><b>Budget</b> ok</li></ul>")
        XCTAssertEqual(DebriefTemplate.html(from: [DebriefRun("• a", bold: true), DebriefRun("b", bold: true)]),
                       "<ul><li><b>ab</b></li></ul>", "morceaux voisins fusionnés")
        XCTAssertEqual(DebriefTemplate.html(from: [DebriefRun("• ", bold: true), DebriefRun("  ", bold: true), DebriefRun("x")]),
                       "<ul><li>x</li></ul>")
    }

    func testEscapingEmptyLinesAndLevelJumps() {
        XCTAssertEqual(DebriefTemplate.html(from: "Titre\r\n• 2 < 3 & 4 > 1\n• \n•\n\n  \n• fin"),
                       "Titre<ul><li>2 &lt; 3 &amp; 4 &gt; 1</li><li>fin</li></ul>")
        XCTAssertEqual(DebriefTemplate.html(from: "Titre\n\t◦ a\n• b"), "Titre<ul><ul><li>a</li></ul><li>b</li></ul>")
        XCTAssertEqual(DebriefTemplate.html(from: "\t\t▪ profond\nTexte\n• puce"),
                       "<ul><ul><ul><li>profond</li></ul></ul></ul><div>Texte</div><ul><li>puce</li></ul>")
        XCTAssertEqual(DebriefTemplate.html(from: "- a\n* b"), "<ul><li>a</li><li>b</li></ul>", "tirets tapés à la main")
    }

    func testParseLineStart() {
        func parsed(_ line: String) -> [Int] {
            let result = DebriefFormat.parse(line)
            return [result.level, result.prefixLength]
        }
        XCTAssertEqual(parsed("• a"), [1, 2])
        XCTAssertEqual(parsed("\t◦ a"), [2, 3])
        XCTAssertEqual(parsed("    - a"), [2, 6], "4 espaces = 1 cran")
        XCTAssertEqual(parsed(" • a"), [1, 3])
        XCTAssertEqual(parsed("-5 %"), [0, 0], "un tiret collé n'est pas une puce")
        XCTAssertEqual(parsed("  texte"), [0, 2])
        XCTAssertEqual(parsed("•"), [1, 1])
        XCTAssertEqual(parsed("\t\t\t\t\t▪ x"), [DebriefFormat.maxLevel, 7])
        XCTAssertEqual(parsed("\t•x"), [0, 1])
        XCTAssertEqual(DebriefFormat.prefix(level: 0), "")
        XCTAssertEqual(DebriefFormat.prefix(level: 1), "• ")
        XCTAssertEqual(DebriefFormat.prefix(level: 3), "\t\t▪ ")
    }

    /// L'historique de l'app affiche la note avec les mêmes retraits.
    func testHistoryShowsTheSameIndentation() {
        var editor = Editor()
        editor.type("Personnes :")
        editor.pressReturn()
        editor.indent()
        editor.type("Camille")
        editor.pressReturn()
        editor.indent()
        editor.type("porte le sujet")
        editor.pressReturn()
        editor.outdent()
        editor.outdent()
        editor.type("Budget")
        let em = "\u{2003}\u{2003}"
        XCTAssertEqual(PlainText.from(html: editor.html),
                       "\(heading)\n• Personnes :\n\(em)◦ Camille\n\(em)\(em)▪ porte le sujet\n• Budget")
    }

    func testHasContent() {
        XCTAssertFalse(DebriefTemplate.hasContent(DebriefFormat.lines(from: DebriefTemplate.starterRuns)))
        XCTAssertFalse(DebriefTemplate.hasContent("\(heading)\n• \n\t◦ \n"))
        XCTAssertTrue(DebriefTemplate.hasContent(DebriefFormat.lines(from: DebriefTemplate.starterRuns + [DebriefRun("ok")])))
    }
}
