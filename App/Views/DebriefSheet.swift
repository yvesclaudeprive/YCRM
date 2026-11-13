import SwiftUI
import PipedriveKit

/// « Debrief call » (demandes d'Yves du 10/11 et du 13/11/2026) : le compte rendu de l'appel s'écrit dans l'app,
/// sans passer par Pipedrive. Chaque retour à la ligne crée une puce ; au-dessus du clavier, « Gauche » / « Droite »
/// décalent la puce et « Gras » met en gras. « Enregistrer » crée l'activité terminée « Call effectué » avec ce texte
/// en note (puces, retraits et gras repris au format Pipedrive), puis la fenêtre « Décaler l'alerte » s'ouvre.
struct DebriefSheet: View {
    let item: ActivityItem
    /// Enregistre le compte rendu dans Pipedrive ; renvoie un message d'erreur, ou nil si c'est fait.
    let save: ([DebriefRun]) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var editor = DebriefEditorController()
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.clientName)
                        .font(.headline)
                    if let name = item.person?.name, !name.isEmpty {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                DebriefTextView(controller: editor)
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ButtonRowStyle.alerts.color.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(ButtonRowStyle.alerts.color.opacity(0.25)))
                    .disabled(saving)
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Color.yateoRed)
                }
                Text("Chaque retour à la ligne crée une puce. Au-dessus du clavier : « Gauche » et « Droite » décalent la puce, « Gras » met en gras. Tout est repris tel quel dans la note Pipedrive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .navigationTitle("Debrief call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Enregistrer") {
                            Task { await submit() }
                        }
                        .fontWeight(.bold)
                        .disabled(!editor.hasContent)
                    }
                }
            }
            .task {
                // Le clavier s'ouvre une fois la fenêtre affichée.
                try? await Task.sleep(nanoseconds: 400_000_000)
                editor.focus()
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.background)
        .interactiveDismissDisabled(saving)
    }

    private func submit() async {
        saving = true
        error = nil
        if let message = await save(editor.runs) {
            error = message
            saving = false
        } else {
            dismiss()
        }
    }
}
