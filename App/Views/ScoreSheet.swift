import SwiftUI
import PipedriveKit

/// « Modifier le score » (demande d'Yves du 25/11/2026) : nouveau « Score priorisation » de l'affaire, verrouillé à la
/// main (« Source de la qualification » = Manuel : le calcul automatique n'y touche plus ; cadenas sur la carte).
struct ScoreSheet: View {
    let item: ActivityItem
    /// Enregistre le score dans Pipedrive ; renvoie un message d'erreur, ou nil si c'est fait.
    let save: (Double) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    init(item: ActivityItem, save: @escaping (Double) async -> String?) {
        self.item = item
        self.save = save
        _text = State(initialValue: item.score.map { FrenchFormat.number($0, maxDecimals: 1) } ?? "")
    }

    private var value: Double? { ScoreInput.parse(text) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.clientName)
                        .font(.headline)
                    if let title = item.deal?.title, !title.isEmpty {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(value.map { ScoreBand(score: $0).color } ?? .secondary)
                    TextField("Score de 0 à 100", text: $text)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                        .focused($focused)
                        .disabled(saving)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.cardAlternate))
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Color.yateoRed)
                } else if !text.isEmpty && value == nil {
                    Text("Un nombre de 0 à 100, par exemple 72 ou 62,5.")
                        .font(.footnote)
                        .foregroundStyle(Color.yateoRed)
                }
                Text(item.scoreIsManual
                     ? "Score déjà verrouillé à la main : il reste en « Manuel » avec la nouvelle valeur."
                     : "Le score sera verrouillé à la main : « Source de la qualification » passe à « Manuel » et le calcul automatique n'y touchera plus. Glisser la carte › « Score auto » pour revenir en automatique.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Modifier le score")
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
                        Button("Enregistrer") {
                            Task { await submit() }
                        }
                        .fontWeight(.bold)
                        .disabled(value == nil)
                    }
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                focused = true
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.background)
        .interactiveDismissDisabled(saving)
    }

    private func submit() async {
        guard let value else { return }
        saving = true
        error = nil
        if let message = await save(value) {
            error = message
            saving = false
        } else {
            dismiss()
        }
    }
}
