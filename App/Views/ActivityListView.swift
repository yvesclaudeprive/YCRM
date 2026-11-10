import SwiftUI
import PipedriveKit

/// Choix d'un numéro ou d'une adresse quand le contact en a plusieurs.
struct ContactPicker: Identifiable {
    struct Choice: Hashable {
        let label: String
        let display: String
        let value: String
        var isEnabled = true
        var note: String?
    }

    let id = UUID()
    let title: String
    let choices: [Choice]
    let onPick: (String) -> Void
}

/// Message bref en bas d'écran, avec « Annuler » après la création d'une activité.
struct Toast: Identifiable {
    let id = UUID()
    let message: String
    var isError = false
    var undo: (@MainActor () async -> Void)?
}

/// Écran principal : mes activités jusqu'à aujourd'hui, triées par score de priorisation.
struct ActivityListView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var feed = ActivityFeedModel()
    @State private var showFilter = false
    @State private var showSettings = false
    @State private var picker: ContactPicker?
    @State private var toast: Toast?
    @State private var busyItemIDs: Set<Int> = []
    @State private var whatsappInstalled = true
    @State private var historySheet: HistoryRequest?
    @State private var quoteSheet: ActivityItem?
    @State private var claudeNote: ActivityItem?
    @State private var rescheduleRequest: RescheduleRequest?
    /// Fenêtre « Debrief call » ouverte ; une fois le compte rendu enregistré, « Décaler l'alerte » s'ouvre ensuite.
    @State private var debriefItem: ActivityItem?
    @State private var pendingReschedule: RescheduleRequest?
    /// Bloc glissé vers la droite (boutons « Note pour Claude » / « Analyse devis » visibles).
    @State private var swipedItemID: Int?
    @State private var explanation: String?

    private enum CallChannel {
        case phone, onoff, aircall, whatsapp, sms
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let progress = feed.tagsProgress {
                    tagsProgressBanner(progress)
                }
                if let error = feed.errorMessage, !feed.items.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Color.yateoRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(feed.visibleItems.enumerated()), id: \.element.id) { index, item in
                    let upcoming = feed.isUpcoming(item)
                    let previous = index > 0 ? feed.visibleItems[index - 1] : nil
                    let groupStarts = previous.map { feed.isUpcoming($0) != upcoming } ?? true
                    if upcoming, groupStarts {
                        sectionHeader(icon: "calendar.badge.clock", text: "À venir", count: feed.upcomingCount)
                    }
                    if item.score == nil, groupStarts || previous?.score != nil {
                        sectionHeader(icon: "number.circle", text: "Sans score",
                                      count: feed.unscoredCount(upcoming: upcoming))
                    }
                    SwipeReveal(actions: swipeActions(for: item), isOpen: swipeBinding(for: item)) {
                        ActivityRow(
                            item: item,
                            isBusy: busyItemIDs.contains(item.id),
                            whatsappInstalled: whatsappInstalled,
                            ownerName: item.activity.ownerID == session.userID ? nil : feed.userName(item.activity.ownerID),
                            isAlternate: !index.isMultiple(of: 2),
                            tags: feed.tags[item.id],
                            perform: { action in handle(action, for: item) }
                        )
                    }
                    .contextMenu {
                        Button("Note pour Claude", systemImage: "bubble.left.and.text.bubble.right") {
                            handle(.noteForClaude, for: item)
                        }
                        Button("Analyse des devis", systemImage: "doc.text.magnifyingglass") {
                            handle(.showQuotes, for: item)
                        }
                    }
                    .onAppear { feed.loadMoreIfNeeded(after: item) }
                    .task(id: feed.tagsGeneration) { await feed.loadTags(for: item, session: session) }
                }
                if feed.canLoadMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .onAppear {
                            if let last = feed.visibleItems.last { feed.loadMoreIfNeeded(after: last) }
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .overlay { placeholder }
        .refreshable { await feed.reload(session: session, fresh: true) }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .overlay(alignment: .bottom) { toastView }
        .task {
            whatsappInstalled = InstalledApps.whatsapp
            if !feed.hasLoaded { await feed.reload(session: session) }
        }
        .sheet(isPresented: $showFilter) {
            FilterView(preset: feed.datePreset, customFrom: feed.customFrom, customTo: feed.customTo,
                       owners: feed.ownerIDs, users: feed.users, myID: session.userID,
                       score: feed.scoreFilter, tags: feed.tagFilters) { preset, from, to, owners, score, tags in
                Task {
                    await feed.applyFilters(preset: preset, from: from, to: to, owners: owners, score: score,
                                            tags: tags, session: session)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
            .presentationBackground(.background)
        }
        .sheet(item: $historySheet) { request in
            HistorySheet(request: request, feed: feed)
        }
        .sheet(item: $quoteSheet) { item in
            QuoteSheet(item: item, tags: feed.tags[item.id] ?? .none, openDeal: {
                open(pipedriveLink(for: item), failure: "Aucune fiche Pipedrive liée à cette activité.")
            }, writeNote: {
                quoteSheet = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    claudeNote = item
                }
            })
        }
        .sheet(item: $rescheduleRequest) { request in
            let item = request.item
            RescheduleSheet(item: item, meeting: feed.tags[item.id]?.nextMeeting(timeZone: parisTimeZone),
                            logged: request.logged, undoLogged: undoAction(for: request)) { day, time in
                Task { await reschedule(item, day: day, parisTime: time) }
            }
        }
        .sheet(item: $debriefItem, onDismiss: {
            // Compte rendu enregistré : on enchaîne sur « Décaler l'alerte » une fois la fenêtre fermée.
            if let next = pendingReschedule {
                pendingReschedule = nil
                rescheduleRequest = next
            }
        }) { item in
            DebriefSheet(item: item) { text in
                await saveDebrief(text, for: item)
            }
        }
        .sheet(item: $claudeNote) { item in
            ClaudeNoteSheet(item: item) { text in
                Task { await sendNoteForClaude(text, for: item) }
            }
        }
        .alert("Bouton indisponible", isPresented: explanationBinding, presenting: explanation) { _ in
            Button("OK", role: .cancel) {}
        } message: { reason in
            Text(reason)
        }
        .sheet(item: $picker) { current in
            ChoiceSheet(picker: current)
        }
    }

    // MARK: Barre du haut : logo, recherche, filtre, réglages

    /// Barre du haut : logo, champ de recherche arrondi, boutons ronds Filtres (point rouge si filtre actif) et Réglages.
    private var header: some View {
        HStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 22)
                .accessibilityLabel("YCRM")
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Société, contact, texte…", text: searchBinding)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !feed.search.isEmpty {
                    Button {
                        feed.updateSearch("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Effacer la recherche")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Capsule().fill(Color.cardPrimary))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
            circleButton(icon: "line.3.horizontal.decrease", label: "Filtres", showsDot: !isDefaultFilter) {
                showFilter = true
            }
            circleButton(icon: "gearshape.fill", label: "Réglages", showsDot: false) {
                showSettings = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private func circleButton(icon: String, label: String, showsDot: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.yateoRed)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.cardPrimary))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                .overlay(alignment: .topTrailing) {
                    if showsDot {
                        Circle()
                            .fill(Color.yateoRed)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Color.cardPrimary, lineWidth: 2))
                            .offset(x: 1, y: -1)
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private var explanationBinding: Binding<Bool> {
        Binding(get: { explanation != nil }, set: { if !$0 { explanation = nil } })
    }

    private var searchBinding: Binding<String> {
        Binding(get: { feed.search }, set: { feed.updateSearch($0) })
    }

    /// Filtre « Étiquettes » : vérification de toute la liste en cours (les activités apparaissent au fur et à mesure).
    private func tagsProgressBanner(_ progress: TagsProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("« \(feed.tagFilters.label) » : vérification de \(progress.done) / \(progress.total) activités…")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .tint(.purple)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.purple.opacity(0.08)))
    }

    /// Bandeau de groupe : « À venir · N activités » (après les retards et le jour),
    /// « Sans score · N activités » (après les activités notées du même groupe).
    private func sectionHeader(icon: String, text: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text("\(text) · \(count) activité\(count > 1 ? "s" : "")")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.horizontal, 4)
    }

    private var isDefaultFilter: Bool {
        feed.isDefaultFilter(myID: session.userID)
    }

    @ViewBuilder
    private var placeholder: some View {
        if !feed.hasLoaded {
            ProgressView("Chargement des activités…")
        } else if let error = feed.errorMessage, feed.items.isEmpty {
            ContentUnavailableView {
                Label("Chargement impossible", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Réessayer") { Task { await feed.reload(session: session) } }
            }
        } else if feed.filteredItems.isEmpty, feed.tagsProgress != nil {
            ProgressView("Recherche des activités « \(feed.tagFilters.label) »…")
        } else if feed.filteredItems.isEmpty {
            if !feed.tagFilters.isAll && feed.search.isEmpty {
                ContentUnavailableView("Aucune activité", systemImage: "tag",
                                       description: Text("Aucune activité avec l'étiquette « \(feed.tagFilters.label) »."))
            } else if feed.search.isEmpty {
                ContentUnavailableView("Aucune activité", systemImage: "checkmark.circle",
                                       description: Text("Rien à faire pour « \(feed.filter.label) ».") )
            } else {
                ContentUnavailableView.search(text: feed.search)
            }
        }
    }

    // MARK: Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            HStack(spacing: 12) {
                Text(toast.message)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                Spacer(minLength: 0)
                if let undo = toast.undo {
                    Button("Annuler") {
                        self.toast = nil
                        Task { await undo() }
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.yellow)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(toast.isError ? Color.yateoRed.opacity(0.95) : Color.black.opacity(0.85)))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func show(_ newToast: Toast) {
        withAnimation { toast = newToast }
        let id = newToast.id
        let delay: Double = newToast.undo == nil ? 3 : 6
        Task {
            try? await Task.sleep(for: .seconds(delay))
            if toast?.id == id {
                withAnimation { toast = nil }
            }
        }
    }

    private func showError(_ message: String) {
        show(Toast(message: message, isError: true))
    }

    // MARK: Actions

    private func handle(_ action: ActivityAction, for item: ActivityItem) {
        switch action {
        case .open:
            open(pipedriveLink(for: item), failure: "Aucune fiche Pipedrive liée à cette activité.")
        case .showHistory, .showLeexi:
            historySheet = HistoryRequest(item: item, section: action.isLeexi ? .leexi : .activities)
            Task { await feed.loadHistory(for: item, session: session) }
        case .showQuotes:
            quoteSheet = item
            Task { await feed.loadTags(for: item, session: session) }
        case .noteForClaude:
            claudeNote = item
        case .reschedule:
            rescheduleRequest = RescheduleRequest(item: item)
        case .openMeeting(let meeting):
            // Lien universel : l'app Google Agenda si elle le prend en charge, sinon Google Agenda dans Safari.
            open(meeting.calendarURL, failure: "Google Agenda n'a pas pu s'ouvrir.")
        case .explain(let reason):
            explanation = reason
        case .openOrganization:
            open(item.orgID.flatMap { ActionLinks.pipedriveOrganization(domain: session.companyDomain, id: $0) },
                 failure: "Aucune société liée à cette activité.")
        case .openPerson:
            open((item.person?.id ?? item.activity.personID).flatMap { ActionLinks.pipedrivePerson(domain: session.companyDomain, id: $0) },
                 failure: "Aucune personne liée à cette activité.")
        // Alertes : activité terminée datée du clic (texte par défaut = nom du type)
        case .voicemailEmpty:
            Task { await logDoneActivity(type: "Répondeur sans message", for: item) }
        case .voicemailOnOff:
            Task { await logDoneActivity(type: "Répondeur ON/OFF", for: item) }
        case .debriefCall:
            // Compte rendu écrit dans l'app (demande d'Yves du 10/11/2026), puis « Décaler l'alerte ».
            debriefItem = item
        case .whatsappSent:
            // Pas de type WhatsApp dans Pipedrive : type « Sms envoyé », texte « WhatsApp envoyé ».
            Task { await logDoneActivity(type: "Sms envoyé", subject: "WhatsApp envoyé", for: item) }
        case .messageColleagues:
            Task { await logDoneActivity(type: "Msg laissé aux collègues", for: item) }
        case .smsSent:
            Task { await logDoneActivity(type: "Sms envoyé", for: item) }
        // Contacter
        case .phone:
            choosePhone(.phone, for: item, title: "Appeler")
        case .onoff:
            choosePhone(.onoff, for: item, title: "Appeler avec OnOff")
        case .aircall:
            choosePhone(.aircall, for: item, title: "Appeler avec Aircall")
        case .whatsapp:
            choosePhone(.whatsapp, for: item, title: "Ouvrir WhatsApp")
        case .sms:
            choosePhone(.sms, for: item, title: "Envoyer un SMS")
        // E-mails
        case .newMail:
            chooseEmail(for: item) { address in
                open(ActionLinks.mailto(to: address), failure: "Aucune app de messagerie n'a pu s'ouvrir.")
            }
        case .replyMail:
            Task { await replyToLastMail(for: item) }
        case .mailToSelf:
            open(ActionLinks.mailto(to: session.myEmail, subject: item.selfMailSubject,
                                    body: pipedriveLink(for: item)?.absoluteString),
                 failure: "Vérifiez votre adresse e-mail dans Réglages.")
        }
    }

    private func pipedriveLink(for item: ActivityItem) -> URL? {
        ActionLinks.pipedrive(domain: session.companyDomain, dealID: item.activity.dealID,
                              personID: item.person?.id ?? item.activity.personID, orgID: item.orgID)
    }

    private func open(_ url: URL?, failure: String) {
        guard let url else {
            showError(failure)
            return
        }
        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in showError(failure) }
            }
        }
    }

    private func choosePhone(_ channel: CallChannel, for item: ActivityItem, title: String) {
        let numbers = item.phoneNumbers
        let usable = channel == .whatsapp ? numbers.filter { PhoneNumber.isLikelyMobile($0.e164) } : numbers
        guard let first = usable.first else {
            showError(channel == .whatsapp ? "Aucun numéro mobile (WhatsApp) pour ce contact." : "Aucun numéro pour ce contact.")
            return
        }
        // Un seul numéro : appel direct. Plusieurs : choix (pour WhatsApp, les fixes sont grisés).
        if numbers.count == 1 {
            call(channel, first.e164)
            return
        }
        picker = ContactPicker(
            title: title,
            choices: numbers.map { number in
                let mobile = PhoneNumber.isLikelyMobile(number.e164)
                let allowed = channel != .whatsapp || mobile
                return ContactPicker.Choice(label: number.label, display: PhoneNumber.display(number.e164),
                                            value: number.e164, isEnabled: allowed,
                                            note: allowed ? nil : "pas de WhatsApp (fixe)")
            }
        ) { number in
            call(channel, number)
        }
    }

    private func call(_ channel: CallChannel, _ number: String) {
        switch channel {
        case .phone:
            open(ActionLinks.phoneCall(number), failure: "Appel impossible depuis cet appareil.")
        case .onoff:
            callWithOnOff(number)
        case .aircall:
            open(ActionLinks.aircall(number), failure: "Aircall n'a pas pu s'ouvrir (app installée ?).")
        case .whatsapp:
            open(ActionLinks.whatsapp(number), failure: "WhatsApp n'a pas pu s'ouvrir.")
        case .sms:
            open(ActionLinks.sms(number), failure: "SMS impossible depuis cet appareil.")
        }
    }

    /// OnOff ne publie aucun lien d'appel : raccourci iPhone, ou lien réglable avec repli
    /// (ouvre OnOff et copie le numéro à coller).
    private func callWithOnOff(_ number: String) {
        if session.onoffMethod == .defaultCallingApp {
            open(ActionLinks.phoneCall(number), failure: "Appel impossible depuis cet appareil.")
            return
        }
        if session.onoffMethod == .shortcut {
            open(ActionLinks.shortcut(named: session.onoffShortcutName, text: number),
                 failure: "Raccourci « \(session.onoffShortcutName) » introuvable : créez-le dans l'app Raccourcis.")
            return
        }
        guard let url = ActionLinks.onoff(number, template: session.onoffTemplate) else {
            openOnOffWithClipboard(number)
            return
        }
        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in openOnOffWithClipboard(number) }
            }
        }
    }

    /// Copie le numéro puis ouvre l'app Number (OnOff) : il ne reste qu'à coller et appeler.
    private func openOnOffWithClipboard(_ number: String) {
        InstalledApps.copyToClipboard(number)
        let display = PhoneNumber.display(number)
        Task {
            if await InstalledApps.openOnOffApp() {
                show(Toast(message: "Numéro \(display) copié : collez-le dans Number."))
            } else {
                show(Toast(message: "Numéro \(display) copié, mais Number ne s'ouvre pas depuis une autre app : ouvrez-la et collez-le."))
            }
        }
    }

    private func chooseEmail(for item: ActivityItem, then action: @escaping (String) -> Void) {
        let emails = item.emailAddresses
        guard let first = emails.first else {
            showError("Aucune adresse e-mail pour ce contact.")
            return
        }
        if emails.count == 1 {
            action(first.address)
            return
        }
        picker = ContactPicker(
            title: "Quelle adresse ?",
            choices: emails.map { ContactPicker.Choice(label: $0.label, display: $0.address, value: $0.address) },
            onPick: action
        )
    }

    /// Alerte Pipedrive (Rép. tel, Répondeur ON/OFF, WhatsApp, Msg laissé aux collègues, Sms envoyé) : activité
    /// terminée datée de maintenant, puis fenêtre « Décaler l'alerte » pour fixer la prochaine relance (demande d'Yves
    /// du 10/11/2026 : on reste dans l'app, plus d'ouverture de Pipedrive). L'activité s'annule depuis cette fenêtre.
    private func logDoneActivity(type typeName: String, subject: String? = nil, for item: ActivityItem) async {
        busyItemIDs.insert(item.id)
        defer { busyItemIDs.remove(item.id) }
        do {
            let logged = try await createDoneActivity(type: typeName, subject: subject, note: nil, for: item)
            rescheduleRequest = RescheduleRequest(item: item, logged: logged)
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// « Debrief call » : « Call effectué » avec le compte rendu écrit dans l'app ; « Décaler l'alerte » s'ouvre à la
    /// fermeture de la fenêtre. Renvoie le message d'erreur à afficher dans la fenêtre, nil si c'est enregistré.
    private func saveDebrief(_ text: String, for item: ActivityItem) async -> String? {
        do {
            let logged = try await createDoneActivity(type: DebriefTemplate.typeName, subject: nil,
                                                      note: DebriefTemplate.html(from: text), for: item)
            pendingReschedule = RescheduleRequest(item: item, logged: logged)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Crée dans Pipedrive une activité terminée datée de maintenant (type existant, texte par défaut = nom du type).
    private func createDoneActivity(type typeName: String, subject: String?, note: String?,
                                    for item: ActivityItem) async throws -> LoggedAlert {
        let type = try await feed.activityType(named: typeName, session: session)
        let api = try session.makeClient()
        let ownerID = try await session.ensureUserID()
        let label = subject ?? type.name
        let createdID = try await api.createDoneActivity(
            type: type, subject: label, date: Date(), ownerID: ownerID,
            dealID: item.activity.dealID, orgID: item.orgID, personID: item.person?.id ?? item.activity.personID,
            note: note
        )
        feed.invalidateTags(for: item)
        return LoggedAlert(activityID: createdID, label: label)
    }

    // MARK: Glisser le bloc : « Note pour Claude », « Analyse devis »

    private func swipeActions(for item: ActivityItem) -> [SwipeAction] {
        [
            SwipeAction(title: "Note pour\nClaude", icon: "bubble.left.and.text.bubble.right.fill", color: .purple) {
                handle(.noteForClaude, for: item)
            },
            SwipeAction(title: "Analyse\ndevis", icon: "doc.text.magnifyingglass", color: .signingOrange) {
                handle(.showQuotes, for: item)
            },
        ]
    }

    /// Un seul bloc ouvert à la fois.
    private func swipeBinding(for item: ActivityItem) -> Binding<Bool> {
        Binding(get: { swipedItemID == item.id }, set: { swipedItemID = $0 ? item.id : nil })
    }

    /// Enregistre la note sur l'affaire (sinon la personne, sinon la société), avec « Annuler » pendant 6 s.
    private func sendNoteForClaude(_ text: String, for item: ActivityItem) async {
        do {
            let api = try session.makeClient()
            let noteID = try await api.addNote(content: ClaudeNote.html(text), dealID: item.activity.dealID,
                                               personID: item.person?.id ?? item.activity.personID, orgID: item.orgID)
            // Temps réel (demande d'Yves du 08/11/2026) : Claude est prévenu une fois le délai d'annulation passé.
            let trigger = session.makeClaudeTrigger()
            let dealID = item.activity.dealID
            let fire: Task<Void, Never>? = trigger.map { trigger in
                Task {
                    do { try await Task.sleep(for: .seconds(6.5)) } catch { return }
                    do {
                        try await trigger.fire(text: ClaudeTrigger.payload(noteID: noteID, dealID: dealID))
                        // Claude traite la note en 30 s à 1 min : la carte se met à jour toute seule.
                        for delay in [40.0, 40.0, 60.0] {
                            try? await Task.sleep(for: .seconds(delay))
                            if await feed.refreshDeal(for: item, session: session) {
                                show(Toast(message: "✅ Claude a mis à jour l'analyse (\(item.clientName))."))
                                break
                            }
                        }
                    } catch {
                        showError("Note enregistrée, mais Claude n'a pas pu être prévenu : \(error.localizedDescription) Il la lira à 5h17 ou 13h17.")
                    }
                }
            }
            let when = trigger == nil ? "à sa prochaine analyse (5h17 ou 13h17)" : "dans une minute environ"
            show(Toast(message: "✅ Note pour Claude enregistrée (\(item.clientName)) : Claude la traite \(when).") {
                fire?.cancel()
                do {
                    try await session.makeClient().deleteNote(id: noteID)
                    show(Toast(message: "Note annulée."))
                } catch {
                    showError(error.localizedDescription)
                }
            })
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Bouton « Décaler » : nouvelle échéance dans Pipedrive (heure de Paris convertie en UTC), carte déplacée tout de
    /// suite dans la liste, « Annuler » 6 s remet l'ancienne date.
    private func reschedule(_ item: ActivityItem, day: String, parisTime: String?) async {
        let old = item.activity
        let due = Reschedule.due(day: day, parisTime: parisTime, timeZone: parisTimeZone)
        busyItemIDs.insert(item.id)
        defer { busyItemIDs.remove(item.id) }
        do {
            try await session.makeClient().rescheduleActivity(id: old.id, dueDate: due.date, dueTime: due.time)
            let moved = old.withDue(date: due.date, time: due.time)
            feed.replaceActivity(moved)
            show(Toast(message: "✅ Alerte décalée au \(moved.displayDate) (\(item.clientName))") {
                do {
                    try await session.makeClient().rescheduleActivity(id: old.id, dueDate: old.dueDate ?? due.date,
                                                                      dueTime: old.dueTime)
                    feed.replaceActivity(old)
                    show(Toast(message: "Date remise au \(old.displayDate)."))
                } catch {
                    showError(error.localizedDescription)
                }
            })
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// « Annuler » de la fenêtre « Décaler l'alerte » : supprime l'alerte qui vient d'être enregistrée.
    private func undoAction(for request: RescheduleRequest) -> (() async -> Bool)? {
        guard let logged = request.logged else { return nil }
        let item = request.item
        return { await undoActivity(logged.activityID, for: item) }
    }

    /// Supprime l'activité qui vient d'être enregistrée ; vrai si c'est fait.
    @discardableResult
    private func undoActivity(_ id: Int, for item: ActivityItem) async -> Bool {
        do {
            try await session.makeClient().deleteActivity(id: id)
            feed.invalidateTags(for: item)
            show(Toast(message: "Activité annulée."))
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    /// Ouvre dans Superhuman le fil du dernier e-mail échangé avec le contact (retrouvé via Pipedrive).
    private func replyToLastMail(for item: ActivityItem) async {
        guard let personID = item.person?.id ?? item.activity.personID else {
            showError("Aucun contact lié à cette activité.")
            return
        }
        busyItemIDs.insert(item.id)
        defer { busyItemIDs.remove(item.id) }
        do {
            guard let hint = try await session.makeClient().lastMail(
                personID: personID, clientEmails: item.emailAddresses.map(\.address), myEmail: session.myEmail) else {
                showError("Aucun e-mail entre vous et ce contact dans Pipedrive.")
                return
            }
            let fallback = replyDraftURL(subject: hint.subject, item: item)
            guard let threadID = hint.gmailMessageID,
                  let url = ActionLinks.superhumanThread(account: session.myEmail, threadID: threadID,
                                                         template: session.superhumanTemplate) else {
                open(fallback, failure: "Impossible d'ouvrir le dernier e-mail.")
                return
            }
            openURL(url) { accepted in
                if !accepted {
                    Task { @MainActor in open(fallback, failure: "Impossible d'ouvrir le dernier e-mail.") }
                }
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Secours : brouillon « Re: <sujet> » adressé au contact.
    private func replyDraftURL(subject: String, item: ActivityItem) -> URL? {
        guard let address = item.emailAddresses.first?.address else { return nil }
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        let reply = trimmed.lowercased().hasPrefix("re:") ? trimmed : "Re: \(trimmed)"
        return ActionLinks.mailto(to: address, subject: reply)
    }
}

/// Liste des numéros ou adresses, avec ceux qui ne conviennent pas grisés (ex. fixes pour WhatsApp).
struct ChoiceSheet: View {
    let picker: ContactPicker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(picker.choices, id: \.self) { choice in
                Button {
                    dismiss()
                    picker.onPick(choice.value)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(choice.display)
                            .foregroundStyle(choice.isEnabled ? Color.primary : Color.secondary)
                        Text([choice.label, choice.note].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!choice.isEnabled)
            }
            .navigationTitle(picker.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.background)
    }
}

private extension ActivityAction {
    var isLeexi: Bool {
        if case .showLeexi = self { return true }
        return false
    }
}

/// Activité terminée qui vient d'être enregistrée (« Répondeur ON/OFF », « Call effectué »…), annulable depuis la
/// fenêtre « Décaler l'alerte » qui s'ouvre ensuite.
struct LoggedAlert: Hashable {
    let activityID: Int
    let label: String
}

/// Fenêtre « Décaler l'alerte » : ouverte par le bouton « Décaler la date », ou juste après une alerte enregistrée.
struct RescheduleRequest: Identifiable {
    let item: ActivityItem
    var logged: LoggedAlert? = nil
    var id: Int { item.id }
}
