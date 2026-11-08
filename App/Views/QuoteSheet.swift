import SwiftUI
import PipedriveKit

/// Détail des devis d'une affaire (demandes d'Yves du 08/11/2026). Avec l'analyse de Claude (champ « Devis en
/// attente », mise à jour vers 5h et 13h) : devis par devis, en signature / envoyés / signés / abandonnés, avec la
/// raison. Sans analyse : les devis envoyés trouvés par l'app (activités « Devis envoyé », e-mails avec un devis joint).
struct QuoteSheet: View {
    let item: ActivityItem
    let tags: LeadTags
    let openDeal: () -> Void
    let writeNote: () -> Void
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
                    if let analysis = tags.analysis {
                        analysisView(analysis)
                    } else {
                        localView
                    }
                    Button(action: writeNote) {
                        Label("Note pour Claude", systemImage: "bubble.left.and.text.bubble.right.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yateoRed)
                    .padding(.top, 6)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title)
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

    private var title: String {
        if tags.hasSigning { return "En signature" }
        if tags.quotes.isEmpty && tags.hasAccessPending { return "Accès en attente" }
        if tags.isSigned { return "Devis signé" }
        if tags.quotes.count > 1 { return "\(tags.quotes.count) devis envoyés" }
        return tags.quotes.isEmpty ? "Devis" : "Devis envoyé"
    }

    // MARK: Analyse de Claude

    @ViewBuilder
    private func analysisView(_ analysis: QuoteAnalysis) -> some View {
        ForEach(QuoteAnalysis.Status.allCases, id: \.self) { status in
            let entries = analysis.entries(status)
            if !entries.isEmpty {
                Text(status.title.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(entries, id: \.self) { entry in
                    entryCard(entry)
                }
            }
        }
        if analysis.entries.isEmpty {
            Text("Aucun devis trouvé sur cette affaire.")
                .foregroundStyle(.secondary)
        }
        if !analysis.comments.isEmpty {
            Text("TES COMMENTAIRES")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            ForEach(analysis.comments, id: \.self) { comment in
                Text(highlighted(comment))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Text(analysis.footer ?? "Analyse de Claude")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func color(_ status: QuoteAnalysis.Status) -> Color {
        switch status {
        case .signing: return .signingOrange
        case .sent: return .yateoRed
        case .signed: return .green
        case .abandoned: return .gray
        case .access: return .accessBlue
        }
    }

    private func icon(_ status: QuoteAnalysis.Status) -> String {
        switch status {
        case .signing: return "signature"
        case .sent: return "doc.text.fill"
        case .signed: return "checkmark.seal.fill"
        case .abandoned: return "xmark.circle.fill"
        case .access: return "key.fill"
        }
    }

    private func entryCard(_ entry: QuoteAnalysis.Entry) -> some View {
        let color = color(entry.status)
        let ago = entry.day.flatMap { QuoteSent.ago(from: $0, to: FrenchFormat.apiDay(from: Date(), timeZone: parisTimeZone)) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon(entry.status))
                Text(highlighted(entry.title))
                    .fontWeight(.bold)
                Spacer(minLength: 4)
                if let day = entry.day {
                    Text(FrenchFormat.longDate(fromAPI: day, timeZone: parisTimeZone) + (ago.map { " · \($0)" } ?? ""))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(color)
            if let detail = entry.detail {
                Text(highlighted(detail))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(color.opacity(0.25), lineWidth: 1))
    }

    // MARK: Sans analyse : règles de l'app

    @ViewBuilder
    private var localView: some View {
        if let signature = tags.signature {
            signatureCard(signature)
        }
        if tags.quotes.isEmpty {
            Text("Aucun devis envoyé depuis 6 mois sur cette affaire.")
                .foregroundStyle(.secondary)
        }
        ForEach(tags.quotes, id: \.self) { quote in
            card(quote)
        }
        Text("Affaire pas encore analysée par Claude (analyse à 5h17 et 13h17). En attendant : activités « Devis envoyé » et e-mails de l'agence au client avec un devis joint (6 derniers mois). « Signé » : affaire gagnée, champ « Contrat signé le », lancement du projet, ou note / activité / e-mail qui dit « signé » (« À la suite de la signature du bon de commande », « Bon pour accord ») après le dernier devis.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
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
                Image(systemName: quote.source == .mail ? "envelope.fill" : "doc.text.fill")
                Text(quote.agoText(timeZone: parisTimeZone).map { "Envoyé \($0)" } ?? "Envoyé")
                    .fontWeight(.bold)
                Spacer(minLength: 4)
                Text(quote.dateText)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(Color.yateoRed)
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
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.yateoRed.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.yateoRed.opacity(0.2), lineWidth: 1))
    }
}
