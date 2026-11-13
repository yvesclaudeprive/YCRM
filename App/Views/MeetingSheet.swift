import SwiftUI
import PipedriveKit

/// « Créer un RDV » (demande d'Yves du 13/11/2026) : date, heure et durée du rendez-vous convenu au téléphone. L'app le
/// crée dans Google Agenda en invitant le contact (avec un lien Google Meet), puis ouvre le brouillon du mail de
/// confirmation dans Superhuman : Yves n'a plus qu'à appuyer sur Envoyer.
struct MeetingSheet: View {
    let item: ActivityItem
    let googleConnected: Bool
    /// Crée le rendez-vous dans Google Agenda (invitation envoyée par Google).
    let create: (MeetingRequest) async throws -> CreatedMeeting
    /// Rendez-vous créé : l'écran parent ouvre le brouillon une fois la fenêtre fermée.
    let created: (MeetingRequest, CreatedMeeting) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start = MeetingInvite.defaultStart(timeZone: parisTimeZone)
    @State private var minutes = 30
    @State private var email = ""
    @State private var title = ""
    @State private var withMeet = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.clientName)
                            .font(.headline)
                        if let name = item.person?.name, !name.isEmpty {
                            Text(name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !googleConnected {
                    Section {
                        Label("Connectez d'abord Google Agenda : Réglages › Google Agenda (une seule fois).",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.yateoRed)
                    }
                }

                Section("Quand") {
                    DatePicker("Date et heure", selection: $start, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                    Picker("Durée", selection: $minutes) {
                        ForEach(MeetingInvite.durations, id: \.self) { value in
                            Text(value == 60 ? "1 h" : "\(value) min").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if item.emailAddresses.count > 1 {
                        Picker("Invité", selection: $email) {
                            ForEach(item.emailAddresses.map { $0.address }, id: \.self) { address in
                                Text(address).tag(address)
                            }
                        }
                    } else {
                        LabeledContent("Invité", value: email)
                    }
                    TextField("Titre du rendez-vous", text: $title)
                    Toggle("Lien Google Meet", isOn: $withMeet)
                } header: {
                    Text("Invitation")
                } footer: {
                    Text("Google envoie l'invitation à l'invité. Ensuite, le brouillon « \(MeetingInvite.mailSubject(start: start, timeZone: parisTimeZone)) » s'ouvre dans Superhuman : il ne reste qu'à l'envoyer.")
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color.yateoRed)
                    }
                }
            }
            .environment(\.timeZone, parisTimeZone)
            .environment(\.locale, Locale(identifier: "fr_FR"))
            .navigationTitle("Créer un RDV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Créer") {
                            Task { await submit() }
                        }
                        .fontWeight(.bold)
                        .disabled(!canCreate)
                    }
                }
            }
            .onAppear {
                if email.isEmpty { email = item.emailAddresses.first?.address ?? "" }
                if title.isEmpty { title = MeetingInvite.defaultTitle(client: item.clientName) }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.background)
        .interactiveDismissDisabled(saving)
    }

    private var canCreate: Bool {
        googleConnected && email.contains("@") && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && start > Date()
    }

    private func submit() async {
        saving = true
        error = nil
        let request = MeetingRequest(title: title.trimmingCharacters(in: .whitespacesAndNewlines), start: start,
                                     minutes: minutes, attendeeEmail: email, withMeet: withMeet, description: nil)
        do {
            let meeting = try await create(request)
            created(request, meeting)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            saving = false
        }
    }
}
