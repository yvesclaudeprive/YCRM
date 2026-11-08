import Foundation
import Observation
import PipedriveKit

/// Historique d'une activité (notes + activités commentées, et appels Leexi), chargé à l'ouverture d'un menu.
enum HistoryState {
    case loading
    case loaded(HistoryBundle)
    case failed(String)
}

/// Les deux fenêtres d'historique d'un bloc.
enum HistorySection: String {
    case activities, leexi
}

/// État de la liste : chargement, filtre de dates, recherche, affichage par pages.
@MainActor
@Observable
final class ActivityFeedModel {
    static let pageSize = 30

    private(set) var items: [ActivityItem] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    // Filtres : période (défaut « jusqu'à aujourd'hui ») et utilisateurs (défaut : moi).
    private(set) var datePreset: DatePreset = .untilToday
    private(set) var customFrom = Date()
    private(set) var customTo = Date()
    private(set) var ownerIDs: Set<Int> = []
    private(set) var users: [PipedriveUser] = []

    var filter: ActivityDateFilter {
        datePreset.filter(timeZone: parisTimeZone, customFrom: customFrom, customTo: customTo)
    }
    private(set) var search = ""
    private(set) var visibleCount = ActivityFeedModel.pageSize
    private var activityTypes: [ActivityType] = []
    private(set) var history: [Int: HistoryState] = [:]
    /// Étiquettes « Devis envoyé » / « 1er call à faire », par activité, calculées quand la carte apparaît.
    private(set) var tags: [Int: LeadTags] = [:]
    private var tagsInFlight: Set<Int> = []
    /// Incrémenté quand des étiquettes doivent être recalculées (les cartes visibles relancent leur calcul).
    private(set) var tagsGeneration = 0

    var filteredItems: [ActivityItem] {
        items.filter { $0.matches(search: search) }
    }

    var visibleItems: [ActivityItem] {
        Array(filteredItems.prefix(visibleCount))
    }

    var canLoadMore: Bool {
        visibleCount < filteredItems.count
    }

    func reload(session: AppSession) async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            let api = try session.makeClient()
            let myID = try await session.ensureUserID()
            if ownerIDs.isEmpty { ownerIDs = [myID] }
            if users.isEmpty { users = (try? await api.users()) ?? [] }
            items = try await ActivityFeedLoader(client: api).load(ownerIDs: Array(ownerIDs), filter: filter,
                                                                   timeZone: parisTimeZone)
            visibleCount = Self.pageSize
            history = [:]
            tags = [:]
            tagsGeneration += 1
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSearch(_ text: String) {
        search = text
        visibleCount = Self.pageSize
    }

    func applyFilters(preset: DatePreset, from: Date, to: Date, owners: Set<Int>, session: AppSession) async {
        datePreset = preset
        customFrom = from
        customTo = to
        if !owners.isEmpty { ownerIDs = owners }
        await reload(session: session)
    }

    /// Filtres d'origine : jusqu'à aujourd'hui, mes activités.
    func isDefaultFilter(myID: Int?) -> Bool {
        datePreset == .untilToday && (ownerIDs.isEmpty || ownerIDs == Set([myID].compactMap { $0 }))
    }

    func userName(_ id: Int?) -> String? {
        guard let id else { return nil }
        return users.first { $0.id == id }?.name
    }

    var ownersSummary: String {
        if ownerIDs.count <= 1 {
            return ownerIDs.first.flatMap { userName($0) } ?? "moi"
        }
        return "\(ownerIDs.count) utilisateurs"
    }

    /// Pagination au scroll : quand la dernière ligne affichée apparaît, on en montre 30 de plus.
    func loadMoreIfNeeded(after item: ActivityItem) {
        guard canLoadMore, item.id == visibleItems.last?.id else { return }
        visibleCount += Self.pageSize
    }

    /// Charge l'historique d'un bloc (une fois) : notes et activités commentées, et appels Leexi.
    func loadHistory(for item: ActivityItem, session: AppSession) async {
        switch history[item.id] {
        case .loaded?, .loading?: return
        default: break
        }
        history[item.id] = .loading
        do {
            try await loadActivityTypes(session: session)
            let names = Dictionary(activityTypes.map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
            let myID = try await session.ensureUserID()
            // Historique de la personne à qui l'activité est attribuée (pas les appels des collègues).
            let ownerID = item.activity.ownerID ?? myID
            let ownerEmail = ownerID == myID ? session.myEmail : users.first { $0.id == ownerID }?.email
            let bundle = try await HistoryLoader(client: session.makeClient()).load(
                for: item, typeNames: names, ownerID: ownerID, ownerEmail: ownerEmail)
            history[item.id] = .loaded(bundle)
        } catch {
            history[item.id] = .failed(error.localizedDescription)
        }
    }

    /// Calcule les étiquettes d'une carte (une fois ; erreurs ignorées : pas d'étiquette plutôt qu'un message).
    func loadTags(for item: ActivityItem, session: AppSession) async {
        guard tags[item.id] == nil, !tagsInFlight.contains(item.id) else { return }
        tagsInFlight.insert(item.id)
        defer { tagsInFlight.remove(item.id) }
        do {
            try await loadActivityTypes(session: session)
            let names = Dictionary(activityTypes.map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
            let result = try await LeadTagsLoader(client: session.makeClient()).load(
                for: item, typeNames: names, timeZone: parisTimeZone)
            guard !Task.isCancelled else { return }
            tags[item.id] = result
        } catch {
            // Carte quittée ou erreur réseau : on réessaiera à la prochaine apparition.
        }
    }

    /// Après une alerte enregistrée ou annulée : recalcule les étiquettes des cartes du même contact / de la même affaire.
    func invalidateTags(for item: ActivityItem) {
        let dealID = item.activity.dealID
        let personID = item.person?.id ?? item.activity.personID
        for other in items {
            let sameDeal = dealID != nil && other.activity.dealID == dealID
            let samePerson = personID != nil && (other.person?.id ?? other.activity.personID) == personID
            if sameDeal || samePerson { tags[other.id] = nil }
        }
        tagsGeneration += 1
    }

    private func loadActivityTypes(session: AppSession) async throws {
        if activityTypes.isEmpty {
            activityTypes = try await session.makeClient().activityTypes()
        }
    }

    /// Type d'activité Pipedrive par son nom (liste chargée une fois).
    func activityType(named name: String, session: AppSession) async throws -> ActivityType {
        try await loadActivityTypes(session: session)
        guard let type = ActivityType.named(name, in: activityTypes) else {
            throw PipedriveError.validation("Type d'activité « \(name) » introuvable dans Pipedrive.")
        }
        return type
    }
}
