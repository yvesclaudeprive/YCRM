import SwiftUI
import PipedriveKit

/// Bouton « Décaler » (demande d'Yves du 09/11/2026) : choisir une nouvelle date pour l'alerte. Choix rapides malins
/// (jamais le week-end), calendrier pour n'importe quelle date, heure gardée ou modifiable ; « Décaler » modifie
/// l'échéance dans Pipedrive.
struct RescheduleSheet: View {
    let item: ActivityItem
    /// Prochain rendez-vous avec le contact : son jour est le premier choix, sélectionné d'office.
    var meeting: UpcomingMeeting? = nil
    /// Alerte qui vient d'être enregistrée (« Répondeur ON/OFF », « Call effectué »…) : bandeau en haut, annulable.
    var logged: LoggedAlert? = nil
    /// Supprime l'alerte enregistrée ; vrai si c'est fait (la fenêtre se ferme alors).
    var undoLogged: (() async -> Bool)? = nil
    /// Jour (AAAA-MM-JJ, Paris) et heure de Paris (« 14:30 ») choisis, nil = sans heure.
    let confirm: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var choices: [RescheduleChoice] = []
    @State private var selectedChoice: String?
    @State private var date = Date()
    @State private var hasTime = false
    @State private var time = Date()
    @State private var undoing = false

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let logged {
                        loggedBanner(logged)
                    }
                    header
                    quickChoices
                    calendar
                    timeRow
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) { confirmButton }
            .navigationTitle(logged == nil ? "Décaler l'alerte" : "Prochaine relance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.background)
        .onAppear(perform: setUp)
    }

    /// « ✅ « Répondeur ON/OFF » enregistré » + « Annuler » (supprime l'activité et ferme la fenêtre).
    private func loggedBanner(_ logged: LoggedAlert) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("« \(logged.label) » enregistré dans Pipedrive")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let undoLogged {
                Button {
                    undoing = true
                    Task {
                        if await undoLogged() { dismiss() }
                        undoing = false
                    }
                } label: {
                    if undoing {
                        ProgressView()
                    } else {
                        Text("Annuler")
                            .font(.subheadline.bold())
                    }
                }
                .tint(Color.yateoRed)
                .disabled(undoing)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.green.opacity(0.1)))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.clientName)
                .font(.headline)
            Text(item.activity.subject)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !item.activity.displayDate.isEmpty {
                Text("Prévue : \(item.activity.displayDate)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickChoices: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(choices) { choice in
                let selected = selectedChoice == choice.id
                Button {
                    selectedChoice = choice.id
                    if let day = FrenchFormat.date(fromAPIDay: choice.day, timeZone: parisTimeZone) { date = day }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(choice.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? .white : .primary)
                        Text(choice.dateText)
                            .font(.caption)
                            .foregroundStyle(selected ? .white.opacity(0.9) : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected ? ButtonRowStyle.mails.color : ButtonRowStyle.mails.color.opacity(0.08))
                    )
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private var calendar: some View {
        DatePicker("Autre date", selection: dateBinding, in: today..., displayedComponents: .date)
            .datePickerStyle(.graphical)
            .tint(ButtonRowStyle.mails.color)
            .environment(\.locale, Locale(identifier: "fr_FR"))
            .environment(\.timeZone, parisTimeZone)
    }

    private var timeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Heure précise", isOn: $hasTime)
                .tint(ButtonRowStyle.mails.color)
            if hasTime {
                DatePicker("Heure", selection: $time, displayedComponents: .hourAndMinute)
                    .environment(\.locale, Locale(identifier: "fr_FR"))
                    .environment(\.timeZone, parisTimeZone)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.secondary.opacity(0.08)))
    }

    private var confirmButton: some View {
        Button {
            confirm(selectedDay, hasTime ? selectedTime : nil)
            dismiss()
        } label: {
            Text("Décaler au \(summary)")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(ButtonRowStyle.mails.color)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Le calendrier enlève le choix rapide sélectionné s'il ne correspond plus.
    private var dateBinding: Binding<Date> {
        Binding(get: { date }, set: { newValue in
            date = newValue
            let day = FrenchFormat.apiDay(from: newValue, timeZone: parisTimeZone)
            selectedChoice = choices.first { $0.day == day }?.id
        })
    }

    private var selectedDay: String { FrenchFormat.apiDay(from: date, timeZone: parisTimeZone) }

    private var selectedTime: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = parisTimeZone
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return String(format: "%02ld:%02ld", parts.hour ?? 9, parts.minute ?? 0)
    }

    /// « mar. 10 novembre à 14:30 ».
    private var summary: String {
        let day = Reschedule.dateText(selectedDay, timeZone: parisTimeZone)
        return hasTime ? "\(day) à \(selectedTime)" : day
    }

    private func setUp() {
        choices = Reschedule.choices(timeZone: parisTimeZone, meeting: meeting)
        if let first = Reschedule.defaultChoice(choices) {
            selectedChoice = first.id
            date = FrenchFormat.date(fromAPIDay: first.day, timeZone: parisTimeZone) ?? Date()
        }
        // Heure de l'alerte gardée (heure de Paris) ; sans heure, 9:00 proposé si on active « Heure précise ».
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = parisTimeZone
        let current = Reschedule.parisTime(of: item.activity, timeZone: parisTimeZone)
        hasTime = current != nil
        let clock = (current ?? "09:00").split(separator: ":").compactMap { Int($0) }
        time = calendar.date(bySettingHour: clock.first ?? 9, minute: clock.last ?? 0, second: 0, of: Date()) ?? Date()
    }
}
