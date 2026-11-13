import SwiftUI
import UIKit
import PipedriveKit

/// Zone de saisie du « Debrief call » (demande d'Yves du 13/11/2026) : chaque retour à la ligne (tapé, dicté ou
/// collé) crée une puce au même cran, et la barre au-dessus du clavier décale la puce à gauche ou à droite et met
/// en gras. Le texte part dans Pipedrive au format de ses notes (`DebriefTemplate.html(from:)`).
@MainActor
@Observable
final class DebriefEditorController {
    /// Vrai dès que le compte rendu dit quelque chose en plus de la première ligne (bouton « Enregistrer »).
    private(set) var hasContent = false

    @ObservationIgnored private weak var textView: UITextView?
    @ObservationIgnored private var boldButton: UIButton?

    /// Largeur d'un cran de retrait (tabulation) dans la fenêtre.
    private static let indentStep: CGFloat = 24

    nonisolated static func isBold(_ font: UIFont?) -> Bool {
        font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
    }

    static func font(bold: Bool) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .body)
        guard bold, let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    static func attributes(bold: Bool) -> [NSAttributedString.Key: Any] {
        [.font: font(bold: bold), .foregroundColor: UIColor.label]
    }

    // MARK: Mise en place

    func attach(_ view: UITextView) {
        textView = view
        let text = NSMutableAttributedString()
        for run in DebriefTemplate.starterRuns {
            text.append(NSAttributedString(string: run.text, attributes: Self.attributes(bold: run.bold)))
        }
        view.attributedText = text
        view.typingAttributes = Self.attributes(bold: false)
        view.selectedRange = NSRange(location: text.length, length: 0)
        view.inputAccessoryView = makeToolbar()
        textChanged()
    }

    func focus() {
        textView?.becomeFirstResponder()
    }

    /// Le compte rendu, morceau par morceau (gras ou non), pour la note Pipedrive.
    var runs: [DebriefRun] {
        guard let storage = textView?.textStorage else { return [] }
        let string = storage.string as NSString
        var result: [DebriefRun] = []
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            result.append(DebriefRun(string.substring(with: range), bold: Self.isBold(value as? UIFont)))
        }
        return result
    }

    // MARK: Saisie

    /// Texte tapé, dicté ou collé qui contient un retour à la ligne : chaque nouvelle ligne devient une puce
    /// (règles de `DebriefEditing.newline`).
    func insert(_ text: String, replacing range: NSRange) {
        guard let view = textView else { return }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        replace(range, with: lines.first ?? "", attributes: view.typingAttributes)
        for line in lines.dropFirst() {
            apply(DebriefEditing.newline(in: view.text ?? "", selection: currentSelection(view)))
            view.typingAttributes = Self.attributes(bold: false)
            // Ligne collée qui a déjà sa puce : la puce n'est pas doublée.
            let parsed = DebriefFormat.parse(line)
            let content = parsed.level > 0
                ? String(decoding: Array(line.utf16).dropFirst(parsed.prefixLength), as: UTF16.self)
                : line
            replace(view.selectedRange, with: content, attributes: Self.attributes(bold: false))
        }
        view.undoManager?.removeAllActions()
        textChanged()
    }

    /// Bouton « Droite » : la puce (ou les lignes sélectionnées) prend un cran de plus.
    func indent() {
        guard let view = textView else { return }
        apply(DebriefEditing.indent(in: view.text ?? "", selection: currentSelection(view)))
        view.undoManager?.removeAllActions()
        textChanged()
    }

    /// Bouton « Gauche » : un cran de moins ; au 1er cran, la puce redevient une ligne simple.
    func outdent() {
        guard let view = textView else { return }
        apply(DebriefEditing.outdent(in: view.text ?? "", selection: currentSelection(view)))
        view.undoManager?.removeAllActions()
        textChanged()
    }

    /// Bouton « Gras » : met en gras (ou enlève le gras) le texte sélectionné, sinon ce qui va être tapé.
    func toggleBold() {
        guard let view = textView else { return }
        let range = view.selectedRange
        if range.length == 0 {
            var attributes = view.typingAttributes
            attributes[.font] = Self.font(bold: !Self.isBold(attributes[.font] as? UIFont))
            view.typingAttributes = attributes
            updateBoldButton()
            return
        }
        let storage = view.textStorage
        var allBold = true
        storage.enumerateAttribute(.font, in: range) { value, _, stop in
            if !Self.isBold(value as? UIFont) {
                allBold = false
                stop.pointee = true
            }
        }
        storage.beginEditing()
        storage.addAttribute(.font, value: Self.font(bold: !allBold), range: range)
        storage.endEditing()
        view.selectedRange = range
        view.undoManager?.removeAllActions()
        textChanged()
    }

    func textChanged() {
        hasContent = DebriefTemplate.hasContent(DebriefFormat.lines(from: runs))
        applyParagraphStyles()
        updateBoldButton()
    }

    func selectionChanged() {
        updateBoldButton()
    }

    // MARK: Outils

    private func currentSelection(_ view: UITextView) -> DebriefRange {
        DebriefRange(location: view.selectedRange.location, length: view.selectedRange.length)
    }

    private func replace(_ range: NSRange, with text: String, attributes: [NSAttributedString.Key: Any]) {
        guard let view = textView else { return }
        let storage = view.textStorage
        guard range.location >= 0, NSMaxRange(range) <= storage.length, range.length > 0 || !text.isEmpty else { return }
        storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: attributes))
        view.selectedRange = NSRange(location: range.location + (text as NSString).length, length: 0)
    }

    /// Applique les modifications calculées par `DebriefEditing` (début de ligne seulement : le gras du texte reste).
    private func apply(_ change: DebriefChange?) {
        guard let change, let view = textView else { return }
        let storage = view.textStorage
        storage.beginEditing()
        for edit in change.edits {
            let range = NSRange(location: edit.range.location, length: edit.range.length)
            guard range.location >= 0, NSMaxRange(range) <= storage.length else { continue }
            storage.replaceCharacters(in: range, with: NSAttributedString(string: edit.replacement,
                                                                          attributes: Self.attributes(bold: false)))
        }
        storage.endEditing()
        let location = min(max(change.selection.location, 0), storage.length)
        view.selectedRange = NSRange(location: location, length: min(max(change.selection.length, 0), storage.length - location))
    }

    /// Retrait des lignes longues : la suite d'une puce s'aligne sous son texte, pas sous le symbole.
    private func applyParagraphStyles() {
        guard let view = textView, view.markedTextRange == nil else { return }
        let storage = view.textStorage
        let font = Self.font(bold: false)
        let selection = view.selectedRange
        var location = 0
        storage.beginEditing()
        for line in storage.string.components(separatedBy: "\n") {
            let length = (line as NSString).length
            let style = NSMutableParagraphStyle()
            style.tabStops = (1...DebriefFormat.maxLevel).map {
                NSTextTab(textAlignment: .left, location: CGFloat($0) * Self.indentStep)
            }
            style.defaultTabInterval = Self.indentStep
            style.paragraphSpacing = 3
            let level = DebriefFormat.parse(line).level
            if level > 0 {
                let marker = (DebriefFormat.marker(level: level) + " ") as NSString
                style.headIndent = CGFloat(level - 1) * Self.indentStep + marker.size(withAttributes: [.font: font]).width
            }
            let range = NSRange(location: location, length: min(length + 1, storage.length - location))
            if range.length > 0 {
                storage.addAttribute(.paragraphStyle, value: style, range: range)
            }
            location += length + 1
        }
        storage.endEditing()
        if view.selectedRange != selection {
            view.selectedRange = selection
        }
    }

    private func updateBoldButton() {
        guard let view = textView, let button = boldButton else { return }
        let range = view.selectedRange
        var bold = true
        if range.length == 0 {
            bold = Self.isBold(view.typingAttributes[.font] as? UIFont)
        } else {
            view.textStorage.enumerateAttribute(.font, in: range) { value, _, stop in
                if !Self.isBold(value as? UIFont) {
                    bold = false
                    stop.pointee = true
                }
            }
        }
        button.configuration = Self.buttonConfiguration(title: "Gras", symbol: "bold", active: bold)
    }

    // MARK: Barre au-dessus du clavier

    private func makeToolbar() -> UIToolbar {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let outdent = makeButton(title: "Gauche", symbol: "decrease.indent", label: "Décaler la puce à gauche") { [weak self] in
            self?.outdent()
        }
        let indent = makeButton(title: "Droite", symbol: "increase.indent", label: "Décaler la puce à droite") { [weak self] in
            self?.indent()
        }
        let bold = makeButton(title: "Gras", symbol: "bold", label: "Gras") { [weak self] in
            self?.toggleBold()
        }
        boldButton = bold
        let done = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.textView?.resignFirstResponder()
            }
        })
        toolbar.items = [UIBarButtonItem(customView: outdent), UIBarButtonItem(customView: indent),
                         UIBarButtonItem(customView: bold), .flexibleSpace(), done]
        toolbar.sizeToFit()
        return toolbar
    }

    private func makeButton(title: String, symbol: String, label: String,
                            action: @escaping @MainActor () -> Void) -> UIButton {
        let button = UIButton(configuration: Self.buttonConfiguration(title: title, symbol: symbol, active: false),
                              primaryAction: UIAction { _ in
                                  MainActor.assumeIsolated { action() }
                              })
        button.accessibilityLabel = label
        return button
    }

    private static func buttonConfiguration(title: String, symbol: String, active: Bool) -> UIButton.Configuration {
        var configuration = active ? UIButton.Configuration.filled() : UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: symbol)
        configuration.title = title
        configuration.imagePadding = 4
        configuration.buttonSize = .small
        configuration.cornerStyle = .capsule
        return configuration
    }
}

/// Le `UITextView` du compte rendu (SwiftUI n'offre pas la main sur la touche retour ni sur le gras).
struct DebriefTextView: UIViewRepresentable {
    let controller: DebriefEditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.allowsEditingTextAttributes = false
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        controller.attach(view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let controller: DebriefEditorController

        init(controller: DebriefEditorController) {
            self.controller = controller
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text.contains("\n") || text.contains("\r") else { return true }
            controller.insert(text, replacing: range)
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            controller.textChanged()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            controller.selectionChanged()
        }
    }
}
