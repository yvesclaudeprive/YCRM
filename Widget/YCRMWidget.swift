import Security
import SwiftUI
import WidgetKit
import PipedriveKit

/// Widget de l'écran de gauche (demande d'Yves du 25/11/2026) : une barre de recherche qui ouvre la recherche de
/// l'app et les premières alertes de la liste (même ordre que l'app : en retard et du jour d'abord, par score),
/// avec leur score ; toucher une alerte ouvre sa fiche Pipedrive. Le widget lit Pipedrive lui-même (jeton du
/// trousseau de l'app) toutes les 30 min environ, et l'app le relance quand elle passe en arrière-plan.
@main
struct YCRMWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlertsWidget()
    }
}

struct AlertsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YCRMAlerts", provider: AlertsProvider()) { entry in
            AlertsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("YCRM")
        .description("Recherche et premières alertes, triées par score.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

let parisTimeZone = TimeZone(identifier: "Europe/Paris") ?? .current

// MARK: Données

struct AlertsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// Pas de données à jour : on montre les dernières connues (ou le message).
    let isStale: Bool
    let message: String?

    static var sample: AlertsEntry {
        let now = Date()
        let today = FrenchFormat.apiDay(from: now, timeZone: parisTimeZone)
        let alerts = [
            WidgetAlert(id: 1, company: "Entreprise Alpha", person: "Alice Exemple", text: "Relancer pour le devis",
                        score: 72, dueDate: today, dueTime: nil, dealID: nil, personID: nil, orgID: nil),
            WidgetAlert(id: 2, company: "Société Bêta", person: "Bruno Exemple", text: "Rappeler pour les accès",
                        score: 55, dueDate: today, dueTime: nil, dealID: nil, personID: nil, orgID: nil),
            WidgetAlert(id: 3, company: "Groupe Gamma", person: "Chloé Exemple", text: "Envoyer la proposition",
                        score: 31, dueDate: today, dueTime: nil, dealID: nil, personID: nil, orgID: nil),
        ]
        return AlertsEntry(date: now, snapshot: WidgetSnapshot(alerts: alerts, dueCount: 3, updatedAt: now),
                           isStale: false, message: nil)
    }
}

struct AlertsProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlertsEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (AlertsEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
            return
        }
        Task { completion(await AlertsStore.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlertsEntry>) -> Void) {
        Task {
            let entry = await AlertsStore.load()
            // Échec (réseau, iPhone verrouillé) : nouvel essai plus tôt.
            let next = Date().addingTimeInterval(entry.isStale ? 10 * 60 : 30 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

/// Lecture de Pipedrive par le widget, avec les dernières alertes gardées pour quand ce n'est pas possible.
enum AlertsStore {
    private static let cacheKey = "widget-snapshot"

    static func load(now: Date = Date()) async -> AlertsEntry {
        let keychain = KeychainStore(service: SharedKeychain.service)
        let cached = readCache()
        let token = keychain.readWithStatus(SharedKeychain.token)
        guard let apiToken = token.value, !apiToken.isEmpty,
              let domain = keychain.read(SharedKeychain.domain), !domain.isEmpty else {
            let message = token.status == errSecInteractionNotAllowed
                ? "Déverrouillez l'iPhone pour mettre à jour."
                : "Ouvrez YCRM une fois pour afficher vos alertes ici."
            return AlertsEntry(date: now, snapshot: cached, isStale: true, message: cached == nil ? message : nil)
        }
        let client = PipedriveClient(configuration: PipedriveConfiguration(companyDomain: domain, apiToken: apiToken))
        let owner = keychain.read(SharedKeychain.userID).flatMap { Int($0) }
        do {
            let snapshot = try await WidgetFeedLoader(client: client).load(ownerID: owner, timeZone: parisTimeZone, now: now)
            writeCache(snapshot)
            return AlertsEntry(date: now, snapshot: snapshot, isStale: false, message: nil)
        } catch {
            return AlertsEntry(date: now, snapshot: cached, isStale: true,
                               message: cached == nil ? "Pipedrive ne répond pas, nouvel essai dans 10 min." : nil)
        }
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
        switch family {
        case .systemSmall:
            SmallAlertsView(entry: entry)
        case .systemLarge:
            AlertListView(entry: entry, rows: 7, large: true)
        default:
            AlertListView(entry: entry, rows: 3, large: false)
        }
    }
}

/// Moyen et grand : barre de recherche, puis les alertes (chaque ligne ouvre sa fiche Pipedrive).
struct AlertListView: View {
    let entry: AlertsEntry
    let rows: Int
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 8 : 5) {
            HStack(spacing: 8) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 15)
                    .accessibilityLabel("YCRM")
                Link(destination: YCRMLink.search) {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Rechercher")
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Color("SearchField")))
                }
                .accessibilityLabel("Rechercher dans YCRM")
                if let count = entry.snapshot?.dueCount {
                    DueCountBadge(count: count)
                }
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            if snapshot.alerts.isEmpty {
                Spacer(minLength: 0)
                Text("Aucune alerte à traiter.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                let alerts = Array(snapshot.alerts.prefix(rows))
                ForEach(Array(alerts.enumerated()), id: \.element.id) { index, alert in
                    Link(destination: alert.link) {
                        AlertRowView(alert: alert, now: entry.date, large: large)
                    }
                    if large && index < alerts.count - 1 {
                        Divider().opacity(0.6)
                    }
                }
                Spacer(minLength: 0)
                if large {
                    Text(footer(snapshot))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        } else {
            Spacer(minLength: 0)
            Text(entry.message ?? "Chargement…")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }

    private func footer(_ snapshot: WidgetSnapshot) -> String {
        let count = snapshot.dueCount
        let due = count <= 1 ? "\(count) alerte en retard ou du jour" : "\(count) alertes en retard ou du jour"
        return "\(due) · \(snapshot.updatedText(timeZone: parisTimeZone))"
    }
}

/// Une alerte : score, société (et contact en grand), texte de l'alerte, date colorée comme dans l'app.
struct AlertRowView: View {
    let alert: WidgetAlert
    let now: Date
    let large: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ScoreBadge(alert: alert)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(alert.company)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if large, let person = alert.person, !person.isEmpty {
                        Text(person)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(alert.text.isEmpty ? "Sans texte" : alert.text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(alert.shortDate(now: now, timeZone: parisTimeZone))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(alert.status(now: now, timeZone: parisTimeZone)?.color ?? .secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .contentShape(Rectangle())
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
                if let count = entry.snapshot?.dueCount {
                    DueCountBadge(count: count)
                }
            }
            if let snapshot = entry.snapshot {
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
                Text(entry.message ?? "Chargement…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
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
            .font(.system(size: compact ? 11 : 12, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: compact ? 28 : 34)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
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
