import SwiftUI
import PipedriveKit

/// Filtres de la liste : une seule rubrique « Date » (passé, aujourd'hui, futur, personnalisée) et les utilisateurs.
struct FilterView: View {
    let preset: DatePreset
    let customFrom: Date
    let customTo: Date
    let owners: Set<Int>
    let users: [PipedriveUser]
    let myID: Int?
    let score: ScoreFilter
    let onApply: (DatePreset, Date, Date, Set<Int>, ScoreFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPreset: DatePreset = .untilToday
    @State private var from = Date()
    @State private var to = Date()
    @State private var selectedOwners: Set<Int> = []
    @State private var selectedScore: ScoreFilter = .all

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Date", selection: $selectedPreset) {
                        ForEach(DatePreset.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if selectedPreset == .custom {
                        DatePicker("Du", selection: $from, displayedComponents: .date)
                        DatePicker("Au", selection: $to, displayedComponents: .date)
                    }
                } header: {
                    Text("Date")
                } footer: {
                    Text(selectedPreset.filter(timeZone: parisTimeZone, customFrom: from, customTo: to).label)
                }

                Section {
                    Picker("Score", selection: $selectedScore) {
                        ForEach(ScoreFilter.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Score")
                } footer: {
                    Text("Sans score : affaire sans « Score priorisation », ou activité sans affaire. Elles sont affichées après les autres.")
                }

                Section {
                    ForEach(sortedUsers) { user in
                        Button {
                            toggle(user.id)
                        } label: {
                            HStack {
                                Text(user.id == myID ? "\(user.name) (moi)" : user.name)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                if selectedOwners.contains(user.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                    if users.isEmpty {
                        Text("Liste des utilisateurs indisponible.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Utilisateurs")
                } footer: {
                    Text("Activités attribuées aux utilisateurs cochés.")
                }
            }
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer") {
                        onApply(selectedPreset, from, to, selectedOwners, selectedScore)
                        dismiss()
                    }
                    .disabled(selectedOwners.isEmpty)
                }
            }
            .onAppear {
                selectedPreset = preset
                from = customFrom
                to = customTo
                selectedOwners = owners.isEmpty ? Set([myID].compactMap { $0 }) : owners
                selectedScore = score
            }
        }
        .presentationBackground(.background)
    }

    /// Moi d'abord, puis les autres utilisateurs actifs par ordre alphabétique.
    private var sortedUsers: [PipedriveUser] {
        users.filter { $0.isActive || selectedOwners.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.id == myID { return true }
                if rhs.id == myID { return false }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func toggle(_ id: Int) {
        if selectedOwners.contains(id) {
            selectedOwners.remove(id)
        } else {
            selectedOwners.insert(id)
        }
    }
}
