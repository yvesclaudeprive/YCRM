import SwiftUI
import PipedriveKit

/// Détail de l'étiquette « Devis envoyé » (demande d'Yves du 08/11/2026) : tous les devis envoyés sur l'affaire,
/// le plus récent d'abord, avec la date, l'ancienneté et la note de l'activité.
struct QuoteSheet: View {
    let item: ActivityItem
    let tags: LeadTags
    let openDeal: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.clientName)
                            .font(.headline)
                        if let title = item.deal?.title, !title.isEmpty {
                            Text(title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)
                    if tags.quotes.isEmpty {
                        Text("Aucun devis envoyé enregistré sur cette affaire.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(tags.quotes) { quote in
                        card(quote)
                    }
                    Text("D'après les activités terminées « Devis envoyé » (ou dont le texte parle d'un devis envoyé) de l'affaire dans Pipedrive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(tags.quotes.count > 1 ? "\(tags.quotes.count) devis envoyés" : "Devis envoyé")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Affaire") {
                        dismiss()
                        openDeal()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.background)
    }

    private func card(_ quote: QuoteSent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                Text(quote.agoText(timeZone: parisTimeZone).map { "Envoyé \($0)" } ?? "Envoyé")
                    .fontWeight(.bold)
                Spacer(minLength: 4)
                Text(quote.dateText)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(Color.purple)
            Text(highlighted(quote.subject))
                .font(.body.weight(.semibold))
            if let note = quote.note {
                Text(highlighted(note))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.purple.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.purple.opacity(0.2), lineWidth: 1))
    }
}
