import SwiftUI
import PipedriveKit

/// Fenêtre demandée depuis un bloc : historique (notes + activités) ou appels Leexi.
struct HistoryRequest: Identifiable {
    let item: ActivityItem
    let section: HistorySection
    var id: String { "\(item.id)-\(section.rawValue)" }
}

/// Fenêtre plein texte : tout l'historique du contact (cartes colorées par type), ou tous ses appels Leexi.
struct HistorySheet: View {
    let request: HistoryRequest
    let feed: ActivityFeedModel
    @Environment(\.dismiss) private var dismiss
    /// Cartes dépliées (les textes longs sont pliés à 3 lignes au départ ; un toucher plie / déplie).
    @State private var expandedIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.item.clientName)
                            .font(.headline)
                        if let person = request.item.person?.name {
                            Text(person)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)
                    content
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(request.section == .activities ? "Notes et activités" : "Appels Leexi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(allExpanded ? "Tout replier" : "Tout déplier") {
                        expandedIDs = allExpanded ? [] : Set(collapsibleIDs)
                    }
                    .disabled(collapsibleIDs.isEmpty)
                }
            }
        }
        .presentationBackground(.background)
    }

    @ViewBuilder
    private var content: some View {
        switch feed.history[request.item.id] {
        case .loaded(let bundle):
            if request.section == .activities {
                if bundle.entries.isEmpty {
                    empty("Aucune note ni activité commentée de votre part pour ce contact.")
                } else {
                    ForEach(bundle.entries) { entry in
                        HistoryCard(color: entry.kind.color, icon: entry.kind.icon,
                                    secondIcon: entry.badge == HistoryEntry.voiceMessageBadge ? "asset:MsgVocal" : nil,
                                    badge: entry.badge,
                                    date: entry.dateText, title: titleIfUseful(entry.title, kind: entry.kind.label),
                                    text: entry.text, footer: entry.author.map { "par \($0)" },
                                    channelIcon: entry.channel?.icon,
                                    compact: entry.isAutomatic,
                                    isCollapsible: !entry.isAutomatic && HistoryCard.isLong(entry.text),
                                    isExpanded: expandedIDs.contains(entry.id),
                                    onToggle: { toggle(entry.id) })
                    }
                }
            } else if bundle.leexi.isEmpty {
                empty("Aucun appel Leexi avec vous pour ce contact.")
            } else {
                ForEach(bundle.leexi) { call in
                    HistoryCard(color: .purple, icon: "asset:Leexi", badge: "Leexi", date: call.dateText,
                                title: call.title, text: call.summary, footer: nil, link: call.link,
                                isCollapsible: HistoryCard.isLong(call.summary),
                                isExpanded: expandedIDs.contains(call.id),
                                onToggle: { toggle(call.id) })
                }
            }
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        case .loading, nil:
            ProgressView("Chargement…")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }

    /// Identifiants des cartes pliables de la fenêtre.
    private var collapsibleIDs: [String] {
        guard case .loaded(let bundle) = feed.history[request.item.id] else { return [] }
        if request.section == .activities {
            return bundle.entries.filter { !$0.isAutomatic && HistoryCard.isLong($0.text) }.map(\.id)
        }
        return bundle.leexi.filter { HistoryCard.isLong($0.summary) }.map(\.id)
    }

    private var allExpanded: Bool {
        !collapsibleIDs.isEmpty && collapsibleIDs.allSatisfy { expandedIDs.contains($0) }
    }

    private func toggle(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedIDs.contains(id) {
                expandedIDs.remove(id)
            } else {
                expandedIDs.insert(id)
            }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 20)
    }

    /// Titre inutile s'il répète le type (« Note » / « Note »).
    private func titleIfUseful(_ title: String, kind: String) -> String? {
        title.compare(kind, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ? nil : title
    }
}
