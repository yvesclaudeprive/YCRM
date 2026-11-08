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

/// Avancement du calcul de toutes les étiquettes (filtre « Étiquettes » actif).
struct TagsProgress: Equatable {
    var done: Int
    let total: Int
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
    private(set) var datePreset: DatePreset = .defaultPreset
    private(set) var customFrom = Date()
    private(set) var customTo = Date()
    private(set) var ownerIDs: Set<Int> = []
    private(set) var scoreFilter: ScoreFilter = .all
    /// Étiquettes choisies (plusieurs possibles ; vide = toutes les activités).
    private(set) var tagFilters: Set<TagFilter> = []
    private(set) var users: [PipedriveUser] = []

    var filter: ActivityDateFilter {
        datePreset.filter(timeZone: parisTimeZone, customFrom: customFrom, customTo: customTo)
    }
    private(set) var search = ""
    private(set) var visibleCount = ActivityFeedModel.pageSize
    private var activityTypes: [ActivityType] = []
    private(set) var history: [Int: HistoryState] = [:]
    /// Étiquettes « Devis envoyé » / « 1er call à faire », par activité, calculées quand la carte apparaît
    /// (ou pour toute la liste quand le filtre « Étiquettes » est actif). Gardées 15 min entre deux rechargements.
    private(set) var tags: [Int: LeadTags] = [:]
    private var tagsComputedAt: [Int: Date] = [:]
    private var tagsInFlight: Set<Int> = []
    /// Calcul de toutes les étiquettes en cours (nil sinon).
    private(set) var tagsProgress: TagsProgress?
    private var allTagsTask: Task<Void, Never>?
    static let tagsLifetime: TimeInterval = 15 * 60
    /// Incrémenté quand des étiquettes doivent être recalculées (les cartes visibles relancent leur calcul).
    private(set) var tagsGeneration = 0

    var filteredItems: [ActivityItem] {
        items.filter { item in
            guard item.matches(search: search), scoreFilter.matches(item) else { return false }
            guard !tagFilters.isAll else { return true }
            // Filtre « Étiquettes » : seules les activités dont les étiquettes sont déjà calculées et correspondent
            // à au moins une des étiquettes choisies.
            return tags[item.id].map(tagFilters.matches) ?? false
        }
    }

    /// Jour courant à Paris (groupes « en retard / du jour » puis « à venir »).
    var today: String { FrenchFormat.apiDay(from: Date(), timeZone: parisTimeZone) }

    func isUpcoming(_ item: ActivityItem) -> Bool {
        item.isUpcoming(today: today, timeZone: parisTimeZone)
    }

    /// Nombre d'activités à venir dans la liste affichée (bandeau « À venir »).
    var upcomingCount: Int {
        let today = self.today
        return filteredItems.filter { $0.isUpcoming(today: today, timeZone: parisTimeZone) }.count
    }

    /// Nombre d'activités sans score du même groupe (en retard / du jour, ou à venir) : bandeau « Sans score ».
    func unscoredCount(upcoming: Bool) -> Int {
        let today = self.today
        return filteredItems.filter { $0.score == nil && $0.isUpcoming(today: today, timeZone: parisTimeZone) == upcoming }.count
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
            let previousAnalysis = Dictionary(items.map { ($0.id, $0.deal?.quoteAnalysis ?? "") },
                                              uniquingKeysWith: { first, _ in first })
            items = try await ActivityFeedLoader(client: api).load(ownerIDs: Array(ownerIDs), filter: filter,
                                                                   timeZone: parisTimeZone)
            visibleCount = Self.pageSize
            history = [:]
            // Étiquettes récentes conservées (évite de tout recalculer à chaque rechargement)…
            let freshSince = Date().addingTimeInterval(-Self.tagsLifetime)
            for (id, date) in tagsComputedAt where date < freshSince {
                tags[id] = nil
                tagsComputedAt[id] = nil
            }
            // … sauf si l'analyse de Claude de l'affaire a changé depuis (note traitée, passage de 5h17 / 13h17).
            for item in items {
                if let old = previousAnalysis[item.id], old != (item.deal?.quoteAnalysis ?? "") {
                    tags[item.id] = nil
                    tagsComputedAt[item.id] = nil
                }
            }
            tagsGeneration += 1
            errorMessage = nil
            if !tagFilters.isAll { startComputingAllTags(session: session) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSearch(_ text: String) {
        search = text
        visibleCount = Self.pageSize
    }

    func applyFilters(preset: DatePreset, from: Date, to: Date, owners: Set<Int>, score: ScoreFilter,
                      tags tagSelection: Set<TagFilter>, session: AppSession) async {
        let sameQuery = preset == datePreset && owners == ownerIDs
            && (preset != .custom || (from == customFrom && to == customTo))
        scoreFilter = score
        tagFilters = tagSelection.isAll ? [] : tagSelection
        visibleCount = Self.pageSize
        if tagFilters.isAll {
            allTagsTask?.cancel()
            tagsProgress = nil
        }
        // Seuls les filtres de score / d'étiquettes ont changé : pas besoin de recharger Pipedrive.
        if sameQuery && hasLoaded {
            if !tagFilters.isAll { startComputingAllTags(session: session) }
            return
        }
        datePreset = preset
        customFrom = from
        customTo = to
        if !owners.isEmpty { ownerIDs = owners }
        await reload(session: session)
    }

    /// Filtres d'origine : jusqu'à aujourd'hui, mes activités.
    func isDefaultFilter(myID: Int?) -> Bool {
        datePreset == .defaultPreset && scoreFilter == .all && tagFilters.isAll
            && (ownerIDs.isEmpty || ownerIDs == Set([myID].compactMap { $0 }))
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
            let result = try await LeadTagsLoader(client: session.makeClient()).load(
                for: item, typeNames: activityTypeNames, timeZone: parisTimeZone, myEmail: session.myEmail)
            guard !Task.isCancelled else { return }
            store(result, for: item.id)
        } catch {
            // Carte quittée ou erreur réseau : on réessaiera à la prochaine apparition.
        }
    }

    private var activityTypeNames: [String: String] {
        Dictionary(activityTypes.map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private func store(_ result: LeadTags, for id: Int) {
        tags[id] = result
        tagsComputedAt[id] = Date()
    }

    /// Filtre « Étiquettes » actif : calcule les étiquettes de toute la liste, 4 activités à la fois.
    func startComputingAllTags(session: AppSession) {
        allTagsTask?.cancel()
        allTagsTask = Task { await computeAllTags(session: session) }
    }

    private func computeAllTags(session: AppSession) async {
        let pending = items.filter { tags[$0.id] == nil && !tagsInFlight.contains($0.id) }
        guard !pending.isEmpty, let client = try? session.makeClient() else {
            tagsProgress = nil
            return
        }
        try? await loadActivityTypes(session: session)
        let names = activityTypeNames
        let myEmail = session.myEmail
        let ids = Set(pending.map(\.id))
        tagsInFlight.formUnion(ids)
        defer { tagsInFlight.subtract(ids) }
        tagsProgress = TagsProgress(done: 0, total: pending.count)
        await withTaskGroup(of: (Int, LeadTags?).self) { group in
            var queue = pending[...]
            func enqueue() {
                guard let item = queue.popFirst() else { return }
                group.addTask {
                    (item.id, try? await LeadTagsLoader(client: client).load(for: item, typeNames: names,
                                                                            timeZone: parisTimeZone, myEmail: myEmail))
                }
            }
            for _ in 0..<4 { enqueue() }
            for await (id, result) in group {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let result { store(result, for: id) }
                tagsProgress?.done += 1
                enqueue()
            }
        }
        if !Task.isCancelled { tagsProgress = nil }
    }

    /// Relit l'affaire dans Pipedrive (après une « Note pour Claude ») ; si l'analyse de Claude a changé, met à jour les
    /// cartes de l'affaire et recalcule leurs étiquettes. Renvoie true si l'analyse a changé.
    @discardableResult
    func refreshDeal(for item: ActivityItem, session: AppSession) async -> Bool {
        guard let dealID = item.activity.dealID,
              let fresh = try? await ActivityFeedLoader(client: session.makeClient()).deal(id: dealID) else { return false }
        let current = items.first { $0.activity.dealID == dealID }?.deal?.quoteAnalysis ?? ""
        guard current != (fresh.quoteAnalysis ?? "") else { return false }
        items = items.map { $0.activity.dealID == dealID ? $0.withDeal(fresh) : $0 }
        invalidateTags(for: item)
        return true
    }

    /// Après une alerte enregistrée ou annulée : recalcule les étiquettes des cartes du même contact / de la même affaire.
    func invalidateTags(for item: ActivityItem) {
        let dealID = item.activity.dealID
        let personID = item.person?.id ?? item.activity.personID
        for other in items {
            let sameDeal = dealID != nil && other.activity.dealID == dealID
            let samePerson = personID != nil && (other.person?.id ?? other.activity.personID) == personID
            if sameDeal || samePerson {
                tags[other.id] = nil
                tagsComputedAt[other.id] = nil
            }
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
