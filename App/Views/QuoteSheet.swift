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
                    if let signature = tags.signature {
                        signatureCard(signature)
                    }
                    if tags.quotes.isEmpty {
                        Text("Aucun devis envoyé enregistré sur cette affaire.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(tags.quotes) { quote in
                        card(quote)
                    }
                    Text("D'après les activités terminées « Devis envoyé » de l'affaire dans Pipedrive. « Signé » : affaire gagnée, champ « Contrat signé le », ou note / activité qui dit « signé » après le dernier devis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(tags.isSigned ? "Devis signé" : (tags.quotes.count > 1 ? "\(tags.quotes.count) devis envoyés" : "Devis envoyé"))
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

    /// Preuve de signature : verte si elle date du dernier devis ou après, grise sinon (un devis plus récent attend).
    private func signatureCard(_ signature: SignatureEvidence) -> some View {
        let color: Color = tags.isSigned ? .green : .gray
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                Text(tags.isSigned ? "Signé" : "Signé (avant le dernier devis)")
                    .fontWeight(.bold)
                Spacer(minLength: 4)
                Text(signature.dateText)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(color)
            Text(highlighted(signature.text))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text(signature.sourceLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(color.opacity(0.25), lineWidth: 1))
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
