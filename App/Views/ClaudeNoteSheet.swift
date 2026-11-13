import SwiftUI
import PipedriveKit

/// « Note pour Claude » (demande d'Yves du 08/11/2026) : un commentaire enregistré en note sur l'affaire, que
/// l'analyse des devis de Claude lit au passage suivant (3h17 et 12h17) pour corriger cette affaire ou sa façon
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
                        Text("Affaire : \(title)")
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
                Text("Écris ta correction pour Claude, sur cette affaire (ex. « la TMA est signée, la refonte non ») ou sur sa façon de détecter les devis (ex. « un BDC envoyé par Sophie = en signature »). La note est enregistrée sur l'affaire dans Pipedrive ; Claude la traite tout de suite si « Note pour Claude : en temps réel » est réglé, sinon à 3h17 ou 12h17.")
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
