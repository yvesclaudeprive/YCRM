import Foundation

// « Debrief call » (demandes d'Yves du 10/11 et du 13/11/2026) : le compte rendu s'écrit dans l'app, chaque retour à
// la ligne crée une puce, des boutons décalent la puce à droite ou à gauche et mettent en gras ; la note envoyée à
// Pipedrive reprend exactement le format de son éditeur (titre en gras, puis `<ul><li>…</li><ul><li>…</li></ul></ul>` :
// une sous-liste se place directement dans la liste du dessus, comme dans les notes écrites par Yves).

/// Morceau de texte d'une ligne du compte rendu, en gras ou non.
public struct DebriefRun: Hashable, Sendable {
    public var text: String
    public var bold: Bool

    public init(_ text: String, bold: Bool = false) {
        self.text = text
        self.bold = bold
    }
}

/// Ligne du compte rendu : niveau 0 = ligne simple (ex. « Je l'ai eu au téléphone et : »), 1 = puce, 2 = puce
/// décalée d'un cran vers la droite, etc. Le texte ne contient plus le symbole de la puce.
public struct DebriefLine: Hashable, Sendable {
    public var level: Int
    public var runs: [DebriefRun]

    public init(level: Int, runs: [DebriefRun]) {
        self.level = level
        self.runs = runs
    }

    public var text: String { runs.map(\.text).joined() }
}

/// Plage de texte en unités UTF-16, comme `NSRange` (sélection d'un `UITextView`).
public struct DebriefRange: Hashable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int = 0) {
        self.location = location
        self.length = length
    }

    public var end: Int { location + length }
}

/// Remplacement d'une plage du texte (unités UTF-16).
public struct DebriefEdit: Hashable, Sendable {
    public let range: DebriefRange
    public let replacement: String

    public init(range: DebriefRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}

/// Modifications à appliquer (déjà rangées de la fin vers le début du texte) et sélection à remettre ensuite.
public struct DebriefChange: Hashable, Sendable {
    public let edits: [DebriefEdit]
    public let selection: DebriefRange

    public init(edits: [DebriefEdit], selection: DebriefRange) {
        self.edits = edits
        self.selection = selection
    }

    /// Le texte une fois les modifications faites (l'app les applique, elle, en gardant le gras).
    public func apply(to text: String) -> String {
        var units = Array(text.utf16)
        for edit in edits {
            let lower = min(max(edit.range.location, 0), units.count)
            let upper = min(max(edit.range.end, lower), units.count)
            units.replaceSubrange(lower..<upper, with: Array(edit.replacement.utf16))
        }
        return String(decoding: units, as: UTF16.self)
    }
}

/// Lignes du compte rendu ↔ texte de la fenêtre ↔ note HTML Pipedrive.
public enum DebriefFormat {
    /// Nombre de crans possibles (au-delà, « décaler à droite » ne fait plus rien).
    public static let maxLevel = 4

    /// Symbole de la puce selon le cran : « • », « ◦ », puis « ▪ » (comme l'historique de l'app).
    public static func marker(level: Int) -> String {
        ["•", "◦", "▪"][min(max(level, 1), 3) - 1]
    }

    /// Début d'une ligne à puce dans la fenêtre : une tabulation par cran, le symbole et une espace.
    /// Niveau 0 (ligne simple) : rien.
    public static func prefix(level: Int) -> String {
        guard level > 0 else { return "" }
        return String(repeating: "\t", count: level - 1) + marker(level: level) + " "
    }

    /// Symboles reconnus en début de ligne (ceux de l'app, et « - », « * », « – » tapés à la main).
    static let markers: Set<Character> = ["•", "◦", "▪", "-", "*", "–"]

    /// Cran d'une ligne de la fenêtre et longueur (UTF-16) de son début : retrait + symbole + espace pour une puce,
    /// espaces de tête pour une ligne simple. Retrait = tabulations (4 espaces comptent pour une tabulation).
    public static func parse(_ line: String) -> (level: Int, prefixLength: Int) {
        let characters = Array(line)
        var index = 0
        var tabs = 0
        var spaces = 0
        while index < characters.count, characters[index] == "\t" || characters[index] == " " {
            if characters[index] == "\t" { tabs += 1 } else { spaces += 1 }
            index += 1
        }
        if index < characters.count, markers.contains(characters[index]),
           index + 1 == characters.count || characters[index + 1] == " " || characters[index + 1] == "\t" {
            let end = min(index + 2, characters.count)
            let level = min(tabs + spaces / 4 + 1, maxLevel)
            return (level, String(characters[0..<end]).utf16.count)
        }
        return (0, String(characters[0..<index]).utf16.count)
    }

    /// Texte de la fenêtre (en morceaux gras / pas gras) → lignes avec leur cran, symboles retirés.
    public static func lines(from runs: [DebriefRun]) -> [DebriefLine] {
        var raw: [[DebriefRun]] = [[]]
        for run in runs {
            let text = run.text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\u{2028}", with: "\n")
                .replacingOccurrences(of: "\u{2029}", with: "\n")
            for (index, part) in text.components(separatedBy: "\n").enumerated() {
                if index > 0 { raw.append([]) }
                if !part.isEmpty { raw[raw.count - 1].append(DebriefRun(part, bold: run.bold)) }
            }
        }
        return raw.map { pieces -> DebriefLine in
            let parsed = parse(pieces.map(\.text).joined())
            return DebriefLine(level: parsed.level, runs: tidy(drop(parsed.prefixLength, from: pieces)))
        }
    }

    /// Retire les `count` premières unités UTF-16 (le début de ligne) en gardant le gras du reste.
    static func drop(_ count: Int, from runs: [DebriefRun]) -> [DebriefRun] {
        var remaining = count
        var result: [DebriefRun] = []
        for run in runs {
            guard remaining > 0 else {
                result.append(run)
                continue
            }
            let units = Array(run.text.utf16)
            if units.count <= remaining {
                remaining -= units.count
                continue
            }
            result.append(DebriefRun(String(decoding: units[remaining...], as: UTF16.self), bold: run.bold))
            remaining = 0
        }
        return result
    }

    /// Espaces de début et de fin de ligne retirés, morceaux voisins de même graisse fusionnés ; un morceau fait
    /// seulement d'espaces n'est jamais en gras.
    static func tidy(_ runs: [DebriefRun]) -> [DebriefRun] {
        var merged: [DebriefRun] = []
        for var run in runs where !run.text.isEmpty {
            if run.text.allSatisfy({ $0.isWhitespace }) { run.bold = false }
            if let last = merged.last, last.bold == run.bold {
                merged[merged.count - 1].text += run.text
            } else {
                merged.append(run)
            }
        }
        while var first = merged.first {
            while let character = first.text.first, character.isWhitespace { first.text.removeFirst() }
            if first.text.isEmpty {
                merged.removeFirst()
                continue
            }
            merged[0] = first
            break
        }
        while var last = merged.last {
            while let character = last.text.last, character.isWhitespace { last.text.removeLast() }
            if last.text.isEmpty {
                merged.removeLast()
                continue
            }
            merged[merged.count - 1] = last
            break
        }
        return merged
    }

    /// Lignes → note HTML au format de l'éditeur Pipedrive : 1re ligne simple telle quelle, lignes simples suivantes
    /// en `<div>`, puces en `<ul><li>`, puce décalée = `<ul>` placée directement dans la liste du dessus, gras en
    /// `<b>`. Lignes vides et puces vides retirées.
    public static func html(_ lines: [DebriefLine]) -> String {
        var html = ""
        var depth = 0
        for line in lines {
            let content = inlineHTML(line.runs)
            guard !content.isEmpty else { continue }
            if line.level <= 0 {
                html += String(repeating: "</ul>", count: depth)
                depth = 0
                html += html.isEmpty ? content : "<div>\(content)</div>"
            } else {
                let level = min(line.level, maxLevel)
                while depth < level {
                    html += "<ul>"
                    depth += 1
                }
                while depth > level {
                    html += "</ul>"
                    depth -= 1
                }
                html += "<li>\(content)</li>"
            }
        }
        html += String(repeating: "</ul>", count: depth)
        return html
    }

    static func inlineHTML(_ runs: [DebriefRun]) -> String {
        runs.map { run in
            run.bold ? "<b>\(escape(run.text))</b>" : escape(run.text)
        }.joined()
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Saisie dans la fenêtre « Debrief call » : retour à la ligne = nouvelle puce, boutons de retrait.
public enum DebriefEditing {
    struct LineInfo {
        let start: Int
        let length: Int
        let text: String
    }

    static func lineInfos(_ text: String) -> [LineInfo] {
        var result: [LineInfo] = []
        var start = 0
        for line in text.components(separatedBy: "\n") {
            let length = line.utf16.count
            result.append(LineInfo(start: start, length: length, text: line))
            start += length + 1
        }
        return result
    }

    static func lineIndex(at position: Int, in lines: [LineInfo]) -> Int {
        var index = 0
        for (candidate, line) in lines.enumerated() where line.start <= position {
            index = candidate
        }
        return index
    }

    /// Touche « retour » : nouvelle puce au même cran (depuis une ligne simple : puce de 1er cran). Sur une puce
    /// vide, la puce remonte d'un cran (au 1er cran, elle redevient une ligne simple vide), comme dans Notes.
    public static func newline(in text: String, selection: DebriefRange) -> DebriefChange {
        let lines = lineInfos(text)
        let line = lines[lineIndex(at: selection.location, in: lines)]
        let parsed = DebriefFormat.parse(line.text)
        let offset = selection.location - line.start
        let content = String(decoding: Array(line.text.utf16).dropFirst(parsed.prefixLength), as: UTF16.self)
        let isBlank = content.allSatisfy { $0.isWhitespace }

        if selection.length == 0, parsed.level > 0, isBlank {
            let prefix = DebriefFormat.prefix(level: parsed.level - 1)
            let edit = DebriefEdit(range: DebriefRange(location: line.start, length: line.length), replacement: prefix)
            return DebriefChange(edits: [edit], selection: DebriefRange(location: line.start + prefix.utf16.count))
        }
        if selection.length == 0, parsed.level > 0, offset < parsed.prefixLength {
            // Curseur avant le texte de la puce : une puce vide s'ajoute au-dessus.
            let inserted = DebriefFormat.prefix(level: parsed.level) + "\n"
            let edit = DebriefEdit(range: DebriefRange(location: line.start), replacement: inserted)
            return DebriefChange(edits: [edit],
                                 selection: DebriefRange(location: line.start + inserted.utf16.count + parsed.prefixLength))
        }
        if selection.length == 0, parsed.level == 0, offset == 0, !isBlank {
            // Début d'une ligne simple (ex. le titre) : la ligne descend, elle ne devient pas une puce.
            let edit = DebriefEdit(range: DebriefRange(location: line.start), replacement: "\n")
            return DebriefChange(edits: [edit], selection: DebriefRange(location: line.start + 1))
        }
        // Puce coupée en deux : les espaces juste après le curseur ne passent pas sur la nouvelle puce.
        var range = selection
        if selection.length == 0 {
            let rest = Array(line.text.utf16).dropFirst(max(offset, 0))
            range.length = rest.prefix(while: { $0 == 0x20 }).count
        }
        let replacement = "\n" + DebriefFormat.prefix(level: max(parsed.level, 1))
        let edit = DebriefEdit(range: range, replacement: replacement)
        return DebriefChange(edits: [edit], selection: DebriefRange(location: selection.location + replacement.utf16.count))
    }

    /// Bouton « décaler à droite » : les lignes sélectionnées (ou celle du curseur) prennent un cran de plus ;
    /// une ligne simple devient une puce. nil si rien ne bouge.
    public static func indent(in text: String, selection: DebriefRange) -> DebriefChange? {
        shift(text, selection: selection, by: 1)
    }

    /// Bouton « décaler à gauche » : un cran de moins ; une puce de 1er cran redevient une ligne simple.
    public static func outdent(in text: String, selection: DebriefRange) -> DebriefChange? {
        shift(text, selection: selection, by: -1)
    }

    static func shift(_ text: String, selection: DebriefRange, by delta: Int) -> DebriefChange? {
        let lines = lineInfos(text)
        let first = lineIndex(at: selection.location, in: lines)
        var last = lineIndex(at: selection.end, in: lines)
        // Sélection qui finit au tout début d'une ligne : cette ligne n'est pas concernée.
        if selection.length > 0, last > first, lines[last].start == selection.end { last -= 1 }
        var edits: [DebriefEdit] = []
        for index in first...last {
            let line = lines[index]
            // Plusieurs lignes : les lignes vides ne bougent pas.
            if first != last, line.text.allSatisfy({ $0.isWhitespace }) { continue }
            let parsed = DebriefFormat.parse(line.text)
            let level = min(max(parsed.level + delta, 0), DebriefFormat.maxLevel)
            guard level != parsed.level else { continue }
            edits.append(DebriefEdit(range: DebriefRange(location: line.start, length: parsed.prefixLength),
                                     replacement: DebriefFormat.prefix(level: level)))
        }
        guard !edits.isEmpty else { return nil }
        let start = map(selection.location, through: edits)
        let end = map(selection.end, through: edits)
        return DebriefChange(edits: edits.reversed(), selection: DebriefRange(location: start, length: max(end - start, 0)))
    }

    /// Position après les modifications (rangées du début vers la fin) ; une position dans un début de ligne
    /// remplacé se place juste après le nouveau début.
    static func map(_ position: Int, through edits: [DebriefEdit]) -> Int {
        var shift = 0
        for edit in edits {
            let newLength = edit.replacement.utf16.count
            if edit.range.length > 0, position >= edit.range.location, position < edit.range.end {
                return edit.range.location + shift + newLength
            }
            guard position >= edit.range.end else { break }
            shift += newLength - edit.range.length
        }
        return position + shift
    }
}

/// Modèle de compte rendu de l'alerte « Debrief call » (note HTML de l'activité « Call effectué »).
public enum DebriefTemplate {
    public static let typeName = "Call effectué"
    /// Première ligne du compte rendu, en gras comme dans les notes d'Yves.
    public static let heading = "Je l'ai eu au téléphone et :"
    /// Note modèle, au format des notes écrites par Yves dans Pipedrive.
    public static let noteHTML = "<b>Je l'ai eu au téléphone et :</b><ul><li>x</li></ul>"
    /// Texte de départ de la fenêtre : la première ligne et une puce prête à remplir.
    public static let starter = heading + "\n" + DebriefFormat.prefix(level: 1)
    /// Le même, avec la première ligne en gras.
    public static let starterRuns = [DebriefRun(heading, bold: true), DebriefRun("\n" + DebriefFormat.prefix(level: 1))]

    /// Vrai si le compte rendu dit quelque chose en plus de la première ligne et des puces vides.
    public static func hasContent(_ lines: [DebriefLine]) -> Bool {
        lines.contains { line in
            !line.runs.isEmpty && !Label.matches(line.text, heading)
        }
    }

    public static func hasContent(_ text: String) -> Bool {
        hasContent(DebriefFormat.lines(from: [DebriefRun(text)]))
    }

    /// Compte rendu de la fenêtre (avec le gras) → note HTML de l'activité « Call effectué ».
    public static func html(from runs: [DebriefRun]) -> String {
        DebriefFormat.html(DebriefFormat.lines(from: runs))
    }

    /// Compte rendu sans mise en forme → note HTML.
    public static func html(from text: String) -> String {
        html(from: [DebriefRun(text)])
    }
}
