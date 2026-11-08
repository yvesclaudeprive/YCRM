import SwiftUI
import PipedriveKit

/// « Note pour Claude » (demande d'Yves du 08/11/2026) : un commentaire enregistré en note sur l'affaire, que
/// l'analyse des devis de Claude lit au passage suivant (vers 5h et 13h) pour corriger cette affaire ou sa façon
/// de détecter les devis.
struct ClaudeNoteSheet: View {
    let item: ActivityItem
    let send: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.clientName)
                        .font(.headline)
                    if let title = item.deal?.title, !title.isEmpty {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                TextEditor(text: $text)
                    .focused($focused)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.purple.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.purple.opacity(0.25)))
                Text("Pour corriger cette affaire (« la TMA est signée, la refonte non ») ou ma façon de détecter les devis (« un BDC envoyé par Sophie = en signature »). Enregistré en note sur l'affaire ; pris en compte à la prochaine analyse, vers 5h ou 13h.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Note pour Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Envoyer") {
                        send(trimmed)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.background)
    }
}
