import Foundation

/// Construit la liste « mes activités » : activités ouvertes filtrées par date, enrichies (société, personne,
/// score de l'affaire) et triées par score de priorisation.
public struct ActivityFeedLoader: Sendable {
    /// Nom du champ d'affaire utilisé pour le tri (retrouvé par son nom, le code dépend du compte).
    public static let scoreFieldName = "Score priorisation"
    /// Champ d'affaire facultatif « Contrat signé le » (date) : s'il existe, le devis est considéré signé (plus d'étiquette).
    public static let signedFieldName = "Contrat signé le"
    /// Champ d'affaire « Devis en attente (claude) » (texte long, nom choisi par Yves le 08/11/2026) : analyse des
    /// devis écrite par Claude deux fois par jour. Tout champ dont le nom commence par « Devis en attente » convient.
    public static let quoteAnalysisFieldName = "Devis en attente (claude)"

    static func isQuoteAnalysisField(_ name: String) -> Bool {
        Label.normalized(name).hasPrefix("devis en attente")
    }

    let client: PipedriveClient

    public init(client: PipedriveClient) {
        self.client = client
    }

    /// Activités ouvertes des utilisateurs choisis (par défaut : soi-même), filtrées par date.
    public func load(ownerIDs: [Int], filter: ActivityDateFilter, timeZone: TimeZone,
                     now: Date = Date()) async throws -> [ActivityItem] {
        async let fieldsRequest = client.dealFields()
        let client = self.client
        let all = try await withThrowingTaskGroup(of: [Activity].self) { group in
            for ownerID in Set(ownerIDs) {
                group.addTask { try await client.openActivities(ownerID: ownerID, untilDay: filter.to) }
            }
            var merged: [Activity] = []
            for try await page in group { merged += page }
            return merged
        }
        var seen = Set<Int>()
        let activities = all.filter { filter.contains(day: $0.localDay(timeZone: timeZone)) && seen.insert($0.id).inserted }
        let fields = (try? await fieldsRequest) ?? []
        let (scoreCode, signedCode, analysisCode) = Self.codes(in: fields)

        async let dealsRequest = client.deals(ids: activities.compactMap(\.dealID), scoreCode: scoreCode,
                                              signedCode: signedCode, analysisCode: analysisCode)
        async let personsRequest = client.persons(ids: activities.compactMap(\.personID))
        let dealList = try await dealsRequest
        let personList = try await personsRequest
        let deals = Dictionary(dealList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let persons = Dictionary(personList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let orgIDs = activities.compactMap { $0.orgID ?? $0.dealID.flatMap { deals[$0]?.orgID } }
        let orgNames = try await client.organizationNames(ids: orgIDs)

        let items = activities.map { activity in
            let deal = activity.dealID.flatMap { deals[$0] }
            let personID = activity.personID ?? deal?.personID
            let orgID = activity.orgID ?? deal?.orgID
            return ActivityItem(activity: activity, organizationName: orgID.flatMap { orgNames[$0] },
                                person: personID.flatMap { persons[$0] }, deal: deal)
        }
        return ActivityItem.feedOrder(items, today: FrenchFormat.apiDay(from: now, timeZone: timeZone), timeZone: timeZone)
    }

    /// Codes des champs d'affaire lus par l'app (retrouvés par leur nom) : score, « Contrat signé le », analyse de Claude.
    static func codes(in fields: [FieldDefinition]) -> (score: String?, signed: String?, analysis: String?) {
        (fields.first { Label.matches($0.name, scoreFieldName) }?.code,
         fields.first { Label.matches($0.name, signedFieldName) }?.code,
         fields.first { isQuoteAnalysisField($0.name) }?.code)
    }

    /// Affaire relue dans Pipedrive, par exemple après une « Note pour Claude » : l'analyse de Claude a pu changer.
    public func deal(id: Int) async throws -> DealSummary? {
        let fields = (try? await client.dealFields()) ?? []
        let (scoreCode, signedCode, analysisCode) = Self.codes(in: fields)
        return try await client.deals(ids: [id], scoreCode: scoreCode, signedCode: signedCode,
                                      analysisCode: analysisCode).first
    }
}

public extension ActivityItem {
    /// Recherche dans la liste : société, personne, texte de l'alerte, affaire (accents et casse ignorés).
    func matches(search: String) -> Bool {
        let query = Label.normalized(search)
        guard !query.isEmpty else { return true }
        let haystack = [organizationName, person?.name, activity.subject, deal?.title]
            .compactMap { $0 }
            .map(Label.normalized)
            .joined(separator: " ")
        return query.split(separator: " ").allSatisfy { haystack.contains($0) }
    }

    /// Numéros appelables (format international), principal d'abord.
    var phoneNumbers: [(label: String, e164: String)] {
        (person?.phones ?? []).compactMap { point in
            PhoneNumber.e164(point.value).map { (label: point.displayLabel, e164: $0) }
        }
    }

    /// Numéros probablement mobiles (WhatsApp).
    var mobileNumbers: [(label: String, e164: String)] {
        phoneNumbers.filter { PhoneNumber.isLikelyMobile($0.e164) }
    }

    /// Société en majuscules pour le sujet du mail à soi-même : « EDMOND BAUD ».
    var clientNameUppercased: String {
        clientName.uppercased(with: Locale(identifier: "fr_FR"))
    }

    var emailAddresses: [(label: String, address: String)] {
        (person?.emails ?? []).map { (label: $0.displayLabel, address: $0.value) }
    }

    /// Sujet « [NOMDUCLIENT] Texte de l'activité » pour le mail à soi-même.
    var selfMailSubject: String {
        "[\(clientNameUppercased)] \(activity.subject)"
    }
}
