import Security
import SwiftUI
import WidgetKit
import PipedriveKit

/// Widgets de l'écran de gauche (demandes d'Yves du 25/11/2026) :
/// - « YCRM » : une barre de recherche qui ouvre la recherche de l'app, puis les premières alertes de la liste
///   (même ordre que l'app : en retard et du jour d'abord, par score) ;
/// - « YCRM · suite » : les alertes suivantes, à poser sous le premier pour remplir l'écran (iOS limite un widget
///   à la moitié de la hauteur de l'écran).
/// Chaque alerte est une carte séparée, haute (grande zone à toucher), qui ouvre YCRM sur la carte de l'alerte.
/// Le widget lit Pipedrive lui-même (jeton du trousseau de l'app) toutes les 30 min environ ; l'app le relance
/// quand elle passe en arrière-plan.
@main
struct YCRMWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlertsWidget()
        MoreAlertsWidget()
    }
}

struct AlertsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YCRMAlerts", provider: AlertsProvider(part: .first)) { entry in
            AlertsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("YCRM")
        .description("Recherche et premières alertes, triées par score.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct MoreAlertsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YCRMAlertsMore", provider: AlertsProvider(part: .more)) { entry in
            AlertsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("YCRM · suite")
        .description("Les alertes suivantes : à placer sous le widget YCRM pour remplir l'écran.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

let parisTimeZone = TimeZone(identifier: "Europe/Paris") ?? .current

// MARK: Mise en page

/// Premier widget (avec la barre de recherche) ou widget « suite ».
enum WidgetPart: Sendable {
    case first, more
}

/// Hauteur des lignes : autant de lignes que possible, d'au moins 42 points (un doigt), qui se partagent toute la
/// hauteur du widget.
enum WidgetLayout {
    static let padding: CGFloat = 11
    static let headerHeight: CGFloat = 30
    static let headerGap: CGFloat = 7
    static let rowSpacing: CGFloat = 5
    static let minRowHeight: CGFloat = 42
    /// Nombre de lignes du premier widget, retenu pour que le widget « suite » reprenne juste après.
    static let firstRowsKey = "widget-first-rows"

    static func rows(in size: CGSize, header: Bool) -> (count: Int, height: CGFloat) {
        let available = size.height - 2 * padding - (header ? headerHeight + headerGap : 0)
        let count = max(1, Int((available + rowSpacing) / (minRowHeight + rowSpacing)))
        let height = (available - CGFloat(count - 1) * rowSpacing) / CGFloat(count)
        return (count, max(minRowHeight, height))
    }
}

// MARK: Données

/// Ce qu'a donné la lecture de Pipedrive (ou les dernières alertes connues).
struct AlertsData: Sendable {
    let snapshot: WidgetSnapshot?
    /// Pas de données à jour : on montre les dernières connues (ou le message).
    let isStale: Bool
    let message: String?

    static var sample: AlertsData {
        let now = Date()
        let today = FrenchFormat.apiDay(from: now, timeZone: parisTimeZone)
        let names = ["Entreprise Alpha", "Société Bêta", "Groupe Gamma", "Maison Delta", "Atelier Epsilon",
                     "Studio Zêta", "Cabinet Êta", "Agence Thêta", "Boutique Iota", "Labo Kappa", "Domaine Lambda",
                     "Hôtel Mu", "Garage Nu", "Ferme Xi", "Clinique Omicron"]
        let texts = ["Relancer pour le devis", "Rappeler pour les accès", "Envoyer la proposition", "Point sur la refonte"]
        let alerts = names.enumerated().map { index, name in
            WidgetAlert(id: index + 1, company: name, person: "Contact Exemple", text: texts[index % texts.count],
                        score: Double(80 - index * 5), dueDate: today, dueTime: nil, dealID: nil, personID: nil,
                        orgID: nil)
        }
        return AlertsData(snapshot: WidgetSnapshot(alerts: alerts, dueCount: alerts.count, updatedAt: now),
                          isStale: false, message: nil)
    }
}

struct AlertsEntry: TimelineEntry {
    let date: Date
    let data: AlertsData
    /// Première alerte affichée (0 pour le premier widget) et nombre de lignes.
    let start: Int
    let rowCount: Int
    let rowHeight: CGFloat
}

struct AlertsProvider: TimelineProvider {
    let part: WidgetPart

    func placeholder(in context: Context) -> AlertsEntry {
        entry(.sample, shape: shape(context, remember: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (AlertsEntry) -> Void) {
        let shape = shape(context, remember: false)
        if context.isPreview {
            completion(entry(.sample, shape: shape))
            return
        }
        Task {
            let data = await AlertsFetcher.shared.load()
            completion(entry(data, shape: shape))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlertsEntry>) -> Void) {
        let shape = shape(context, remember: true)
        Task {
            let data = await AlertsFetcher.shared.load()
            // Échec (réseau, iPhone verrouillé) : nouvel essai plus tôt.
            let next = Date().addingTimeInterval(data.isStale ? 10 * 60 : 30 * 60)
            completion(Timeline(entries: [entry(data, shape: shape)], policy: .after(next)))
        }
    }

    private struct Shape {
        let start: Int
        let count: Int
        let height: CGFloat
    }

    /// Lignes de ce widget. Le widget « suite » reprend après le dernier rang du premier widget.
    private func shape(_ context: Context, remember: Bool) -> Shape {
        let layout = WidgetLayout.rows(in: context.displaySize, header: part == .first)
        switch part {
        case .first:
            let count = context.family == .systemSmall ? 3 : layout.count
            if remember { UserDefaults.standard.set(count, forKey: WidgetLayout.firstRowsKey) }
            return Shape(start: 0, count: count, height: layout.height)
        case .more:
            let stored = UserDefaults.standard.integer(forKey: WidgetLayout.firstRowsKey)
            let start = stored > 0 ? stored : WidgetLayout.rows(in: context.displaySize, header: true).count
            return Shape(start: start, count: layout.count, height: layout.height)
        }
    }

    private func entry(_ data: AlertsData, shape: Shape) -> AlertsEntry {
        AlertsEntry(date: Date(), data: data, start: shape.start, rowCount: shape.count, rowHeight: shape.height)
    }
}

/// Une seule lecture de Pipedrive pour les deux widgets quand ils se mettent à jour en même temps.
actor AlertsFetcher {
    static let shared = AlertsFetcher()
    private var running: Task<AlertsData, Never>?

    func load() async -> AlertsData {
        if let running { return await running.value }
        if let recent = AlertsStore.recentCache(maxAge: 20) {
            return AlertsData(snapshot: recent, isStale: false, message: nil)
        }
        let task = Task { await AlertsStore.fetch() }
        running = task
        let data = await task.value
        running = nil
        return data
    }
}

/// Lecture de Pipedrive par le widget, avec les dernières alertes gardées pour quand ce n'est pas possible.
enum AlertsStore {
    private static let cacheKey = "widget-snapshot"

    static func fetch(now: Date = Date()) async -> AlertsData {
        let keychain = KeychainStore(service: SharedKeychain.service)
        let cached = readCache()
        let token = keychain.readWithStatus(SharedKeychain.token)
        guard let apiToken = token.value, !apiToken.isEmpty,
              let domain = keychain.read(SharedKeychain.domain), !domain.isEmpty else {
            let message = token.status == errSecInteractionNotAllowed
                ? "Déverrouillez l'iPhone pour mettre à jour."
                : "Ouvrez YCRM une fois pour afficher vos alertes ici."
            return AlertsData(snapshot: cached, isStale: true, message: cached == nil ? message : nil)
        }
        let client = PipedriveClient(configuration: PipedriveConfiguration(companyDomain: domain, apiToken: apiToken))
        let owner = keychain.read(SharedKeychain.userID).flatMap { Int($0) }
        do {
            let snapshot = try await WidgetFeedLoader(client: client).load(ownerID: owner, timeZone: parisTimeZone, now: now)
            writeCache(snapshot)
            return AlertsData(snapshot: snapshot, isStale: false, message: nil)
        } catch {
            return AlertsData(snapshot: cached, isStale: true,
                              message: cached == nil ? "Pipedrive ne répond pas, nouvel essai dans 10 min." : nil)
        }
    }

    /// Alertes lues il y a moins de `maxAge` secondes (l'autre widget vient de les lire).
    static func recentCache(maxAge: TimeInterval) -> WidgetSnapshot? {
        guard let cached = readCache(), Date().timeIntervalSince(cached.updatedAt) < maxAge else { return nil }
        return cached
    }

    private static func readCache() -> WidgetSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    private static func writeCache(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

// MARK: Affichage

struct AlertsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AlertsEntry

    var body: some View {
        if family == .systemSmall {
            SmallAlertsView(entry: entry)
        } else {
            AlertListView(entry: entry, showsHeader: entry.start == 0)
        }
    }
}

/// Moyen et grand : barre de recherche (premier widget), puis une carte par alerte, qui ouvre YCRM sur l'alerte.
struct AlertListView: View {
    let entry: AlertsEntry
    let showsHeader: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetLayout.rowSpacing) {
            if showsHeader {
                header
                    .frame(height: WidgetLayout.headerHeight)
                    .padding(.bottom, WidgetLayout.headerGap - WidgetLayout.rowSpacing)
            }
            content
        }
        .padding(WidgetLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 16)
                .accessibilityLabel("YCRM")
            Link(destination: YCRMLink.search) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Rechercher")
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .frame(maxHeight: .infinity)
                .background(Capsule().fill(Color("RowBackground")))
                .contentShape(Capsule())
            }
            .accessibilityLabel("Rechercher dans YCRM")
            if let count = entry.data.snapshot?.dueCount {
                DueCountBadge(count: count)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.data.snapshot {
            let alerts = Array(snapshot.alerts.dropFirst(entry.start).prefix(entry.rowCount))
            if alerts.isEmpty {
                message(entry.start == 0 ? "Aucune alerte à traiter." : "Pas d'autres alertes.")
            } else {
                ForEach(alerts) { alert in
                    Link(destination: alert.link) {
                        AlertRowView(alert: alert, now: entry.date, height: entry.rowHeight)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            message(entry.data.message ?? "Chargement…")
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Une alerte, en carte séparée sur toute la largeur : score, société et contact, texte de l'alerte, date colorée
/// comme dans l'app. Toute la carte se touche.
struct AlertRowView: View {
    let alert: WidgetAlert
    let now: Date
    let height: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            ScoreBadge(alert: alert)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(alert.company)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let person = alert.person, !person.isEmpty {
                        Text(person)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(alert.text.isEmpty ? "Sans texte" : alert.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(alert.shortDate(now: now, timeZone: parisTimeZone))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(alert.status(now: now, timeZone: parisTimeZone)?.color ?? .secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color("RowBackground")))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Petit : les 3 premières alertes (score + société) ; toucher ouvre la liste de l'app.
struct SmallAlertsView: View {
    let entry: AlertsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 13)
                    .accessibilityLabel("YCRM")
                Spacer(minLength: 0)
                if let count = entry.data.snapshot?.dueCount {
                    DueCountBadge(count: count)
                }
            }
            if let snapshot = entry.data.snapshot {
                if snapshot.alerts.isEmpty {
                    Spacer(minLength: 0)
                    Text("Aucune alerte à traiter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.alerts.prefix(3)) { alert in
                        HStack(spacing: 6) {
                            ScoreBadge(alert: alert, compact: true)
                            Text(alert.company)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text(entry.data.message ?? "Chargement…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(YCRMLink.home)
    }
}

/// Score de l'affaire, coloré par tranches de 20 comme dans l'app (« — » sans score).
struct ScoreBadge: View {
    let alert: WidgetAlert
    var compact = false

    var body: some View {
        let color = alert.score.map { ScoreBand(score: $0).color } ?? Color.secondary.opacity(0.5)
        Text(alert.scoreText ?? "—")
            .font(.system(size: compact ? 11 : 12.5, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: compact ? 28 : 36)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.gradient))
            .accessibilityLabel(alert.scoreText.map { "Score \($0)" } ?? "Sans score")
    }
}

/// Nombre d'alertes en retard ou du jour.
struct DueCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bell.fill")
                .font(.system(size: 9, weight: .bold))
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Capsule().fill(Color.yateoRed.gradient))
        .accessibilityLabel("\(count) alertes en retard ou du jour")
    }
}

extension Color {
    /// Rouge Yateo (lettres « CRM » du logo), comme dans l'app.
    static let yateoRed = Color("YateoRed")
}

extension ScoreBand {
    /// Bleu (< 20) → sarcelle → orange → rouge (≥ 60), comme dans l'app.
    var color: Color {
        switch self {
        case .veryLow: return .blue
        case .low: return .teal
        case .medium: return .orange
        case .high, .veryHigh: return .yateoRed
        }
    }
}

extension DateStatus {
    /// Rouge en retard, orange aujourd'hui, vert à venir, comme dans l'app.
    var color: Color {
        switch self {
        case .overdue: return .yateoRed
        case .today: return .orange
        case .upcoming: return .green
        }
    }
}
