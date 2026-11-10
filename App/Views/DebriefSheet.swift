import SwiftUI
import PipedriveKit

/// « Debrief call » (demande d'Yves du 10/11/2026) : le compte rendu de l'appel s'écrit dans l'app, sans passer par
/// Pipedrive. « Enregistrer » crée l'activité terminée « Call effectué » avec ce texte en note, puis la fenêtre
/// « Décaler l'alerte » s'ouvre : on l'a eu, on note ce qui s'est dit, on fixe la prochaine relance.
struct DebriefSheet: View {
    let item: ActivityItem
    /// Enregistre le compte rendu dans Pipedrive ; renvoie un message d'erreur, ou nil si c'est fait.
    let save: (String) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var text = DebriefTemplate.starter
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool

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
                TextEditor(text: $text)
                    .focused($focused)
                    .frame(minHeight: 200)
                    .padding(8)
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
                Text("Une ligne par point, commencée par « • ». « Enregistrer » crée l'activité « Call effectué » dans Pipedrive avec ce compte rendu, puis propose de décaler l'alerte.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
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
                        .disabled(!DebriefTemplate.hasContent(text))
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.large])
        .presentationBackground(.background)
        .interactiveDismissDisabled(saving)
    }

    private func submit() async {
        saving = true
        error = nil
        if let message = await save(text) {
            error = message
            saving = false
        } else {
            dismiss()
        }
    }
}
