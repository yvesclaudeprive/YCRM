import SwiftUI
import PipedriveKit

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var domain = ""
    @State private var token = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var myEmail = ""
    @State private var onoffTemplate = ""
    @State private var superhumanTemplate = ""
    @State private var savedPreferences = false
    @State private var onoffMethod: OnOffMethod = .link
    @State private var onoffShortcutName = ""
    @State private var detectedOnOff: [String] = []
    @State private var claudeFireURL = ""
    @State private var claudeToken = ""
    @State private var claudeMessage: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 0) {
                    TextField("votre-societe", text: $domain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text(".pipedrive.com")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Adresse Pipedrive")
            }

            Section {
                SecureField(session.hasToken ? "Nouveau jeton" : "Jeton API", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Jeton API personnel")
            } footer: {
                Text("Dans Pipedrive : photo de profil › Préférences personnelles › API. Le jeton est gardé uniquement dans le trousseau de cet iPhone.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Text(session.hasToken ? "Remplacer le jeton" : "Se connecter")
                        if isConnecting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isConnecting || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if session.hasToken {
                Section {
                    TextField("vous@exemple.com", text: $myEmail)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                } header: {
                    Text("Mon adresse e-mail")
                } footer: {
                    Text("Destinataire du bouton « Auto mail » et compte Superhuman du bouton « Répondre dernier mail ».")
                }

                Section {
                    Picker("Méthode", selection: $onoffMethod) {
                        ForEach(OnOffMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    switch onoffMethod {
                    case .link:
                        TextField(ActionLinks.defaultOnOffTemplate, text: $onoffTemplate)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.footnote.monospaced())
                    case .shortcut:
                        TextField("Nom du raccourci", text: $onoffShortcutName)
                            .autocorrectionDisabled()
                    case .defaultCallingApp:
                        Text("Le bouton OnOff ouvre l'app d'appel par défaut de l'iPhone sur le numéro.")
                            .font(.footnote)
                    }
                    LabeledContent("Liens OnOff détectés",
                                   value: detectedOnOff.isEmpty ? "aucun" : detectedOnOff.map { "\($0)://" }.joined(separator: ", "))
                        .font(.footnote)
                } header: {
                    Text("OnOff (app « Number »)")
                } footer: {
                    switch onoffMethod {
                    case .link:
                        Text("{numero} = +33…, {numero_sans_plus} = 33…. Si le lien ne marche pas, l'app ouvre OnOff et copie le numéro à coller.")
                    case .shortcut:
                        Text("Dans l'app Raccourcis, créez un raccourci portant ce nom qui appelle avec OnOff le numéro reçu en entrée.")
                    case .defaultCallingApp:
                        Text("À utiliser si Number est choisi dans Réglages de l'iPhone › Apps › Apps par défaut › Appels. Attention : le bouton « Tél. » ouvrira alors aussi Number.")
                    }
                }

                Section {
                    TextField(ActionLinks.defaultSuperhumanTemplate, text: $superhumanTemplate)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                } header: {
                    Text("Lien Superhuman (bouton « Répondre dernier mail »)")
                } footer: {
                    Text("{compte} = votre adresse, {fil} = identifiant du fil. Pour que « Nouveau mail » et « Auto mail » ouvrent Superhuman : Réglages de l'iPhone › Apps › Apps par défaut › Messagerie › Superhuman.")
                }

                Section {
                    TextField("https://api.anthropic.com/v1/claude_code/routines/…/fire", text: $claudeFireURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.footnote.monospaced())
                    SecureField(session.hasClaudeToken ? "Nouveau jeton (facultatif)" : "Jeton de la tâche", text: $claudeToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Enregistrer") {
                        do {
                            try session.saveClaudeTrigger(fireURL: claudeFireURL, token: claudeToken)
                            claudeToken = ""
                            claudeFireURL = session.claudeFireURL
                            claudeMessage = "✓ Claude sera prévenu à chaque note."
                        } catch {
                            claudeMessage = error.localizedDescription
                        }
                    }
                    .disabled(claudeFireURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let claudeMessage {
                        Text(claudeMessage)
                            .font(.footnote)
                            .foregroundStyle(claudeMessage.hasPrefix("✓") ? Color.green : Color.red)
                    }
                    if session.isClaudeTriggerReady {
                        Button("Ne plus prévenir Claude en temps réel", role: .destructive) {
                            session.removeClaudeTrigger()
                            claudeFireURL = ""
                            claudeMessage = nil
                        }
                    }
                } header: {
                    Text("Note pour Claude : en temps réel")
                } footer: {
                    Text("Sur claude.ai/code/routines, tâche « YCRM · Note pour Claude (temps réel) » › Modifier › Déclencheur + › API : copiez l'adresse (Fire URL) et générez le jeton, puis collez-les ici. Le jeton reste dans le trousseau de cet iPhone. Sans réglage, Claude lit les notes à 5h17 et 13h17.")
                }

                Section {
                    Button(savedPreferences ? "Réglages enregistrés ✓" : "Enregistrer les réglages") {
                        session.savePreferences(myEmail: myEmail, onoffTemplate: onoffTemplate,
                                                superhumanTemplate: superhumanTemplate,
                                                onoffMethod: onoffMethod, onoffShortcutName: onoffShortcutName)
                        loadPreferences()
                        savedPreferences = true
                    }
                }

                Section {
                    Button("Supprimer le jeton de cet iPhone", role: .destructive) {
                        session.disconnect()
                        dismiss()
                    }
                } footer: {
                    Text("Connecté à \(session.companyDomain).pipedrive.com · \(appVersion)")
                }
            }
        }
        .navigationTitle(session.hasToken ? "Réglages" : "Connexion")
        .toolbar {
            if session.hasToken {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .onAppear {
            if domain.isEmpty { domain = session.companyDomain }
            loadPreferences()
        }
    }

    /// « Version 1.0 (build 15) » : pour vérifier que TestFlight a bien installé la dernière version.
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (build \(build))"
    }

    private func loadPreferences() {
        myEmail = session.myEmail
        onoffTemplate = session.onoffTemplate
        superhumanTemplate = session.superhumanTemplate
        onoffMethod = session.onoffMethod
        onoffShortcutName = session.onoffShortcutName
        detectedOnOff = InstalledApps.onoffSchemes
        claudeFireURL = session.claudeFireURL
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            try await session.connect(domain: domain, token: token)
            token = ""
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
