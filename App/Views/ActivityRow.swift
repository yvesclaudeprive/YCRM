import SwiftUI
import PipedriveKit

enum ActivityAction {
    case open
    // Alertes : activité terminée créée dans Pipedrive
    case debriefCall, voicemailEmpty, voicemailOnOff, whatsappSent, messageColleagues, smsSent
    // Contacter : ouvre une autre app
    case phone, onoff, aircall, whatsapp, sms
    // E-mails : brouillons ; « Décaler » : nouvelle date de l'alerte dans Pipedrive
    case newMail, replyMail, mailToSelf, reschedule
    // Historique (fenêtres)
    case showHistory, showLeexi
    /// Étiquette « Devis envoyé » / « En signature » touchée, ou bouton « Analyse devis » : détail des devis.
    case showQuotes
    /// Bouton « Note pour Claude » (bloc glissé vers la droite) : commentaire lu par l'analyse des devis.
    case noteForClaude
    /// Étiquette « RDV à venir » touchée : le rendez-vous dans Google Agenda.
    case openMeeting(UpcomingMeeting)
    /// Bouton grisé touché : on explique pourquoi.
    case explain(String)
}

/// Carte d'une activité : société + score, personne + date, texte, 4 lignes de boutons (bleu / bleu clair).
struct ActivityRow: View {
    let item: ActivityItem
    let isBusy: Bool
    let whatsappInstalled: Bool
    /// Nom de l'utilisateur à qui l'activité est attribuée, s'il ne s'agit pas de moi.
    let ownerName: String?
    /// Fonds alternés d'une carte à l'autre.
    let isAlternate: Bool
    /// Étiquettes « Devis envoyé » / « 1er call à faire » (nil tant qu'elles ne sont pas calculées).
    var tags: LeadTags? = nil
    let perform: (ActivityAction) -> Void

    private static let chipHeight: CGFloat = 54

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            details
                .contentShape(Rectangle())
                .onTapGesture { perform(.open) }
                .accessibilityHint("Ouvrir l'affaire dans Pipedrive")

            VStack(spacing: 8) {
                // Actions (orange) : appeler / écrire.
                buttonRow(.contact, unavailable: phoneReason != nil && whatsappReason != nil) {
                    chip("Appel\ntel.", icon: "phone.fill", action: .phone, row: .contact, disabledReason: phoneReason)
                    chip("Appel\nOnoff", icon: "asset:OnOff", action: .onoff, row: .contact, disabledReason: phoneReason)
                    chip("Appel\nAircall", icon: "asset:Aircall", action: .aircall, row: .contact, disabledReason: phoneReason)
                    chip("Envoi\nWhatsApp", icon: "asset:WhatsApp", action: .whatsapp, row: .contact,
                         disabledReason: whatsappReason)
                    chip("Envoi\nSMS", icon: "message.fill", action: .sms, row: .contact, disabledReason: phoneReason)
                }
                buttonRow(.mails, unavailable: false) { // « Auto mail » est toujours possible.
                    chip("Nouveau\nmail", icon: "envelope.fill", action: .newMail, row: .mails, disabledReason: emailReason)
                    chip("Répondre\ndernier mail", icon: "arrowshape.turn.up.left.fill", action: .replyMail, row: .mails,
                         disabledReason: personReason ?? busyReason)
                    chip("Auto\nmail", icon: "paperplane.fill", action: .mailToSelf, row: .mails, disabledReason: nil)
                    chip("Décaler\nla date", icon: "calendar.badge.clock", action: .reschedule, row: .mails,
                         disabledReason: busyReason, pipedrive: true)
                }
                // Historique (bleu) : ce qui s'enregistre ou se consulte dans Pipedrive.
                buttonRow(.alerts, unavailable: busyReason != nil) {
                    chip("Debrief\ncall", icon: "text.badge.checkmark", action: .debriefCall, row: .alerts,
                         disabledReason: busyReason, pipedrive: true)
                    chip("Rép.\ntel", icon: "phone.down.fill", action: .voicemailEmpty, row: .alerts,
                         disabledReason: busyReason, pipedrive: true)
                    chip("Rép.\nON/OFF", icon: "asset:OnOff", action: .voicemailOnOff, row: .alerts,
                         disabledReason: busyReason, pipedrive: true)
                    chip("WhatsApp", icon: "asset:WhatsApp", action: .whatsappSent, row: .alerts,
                         disabledReason: busyReason, pipedrive: true)
                    chip("Msg\ncollègues", icon: "person.2.fill", action: .messageColleagues, row: .alerts,
                         disabledReason: busyReason, pipedrive: true)
                    chip("SMS\nenvoyé", icon: "text.bubble.fill", action: .smsSent, row: .alerts,
                         disabledReason: busyReason, pipedrive: true)
                }
                HStack(spacing: 8) {
                    historyButton("Dernières notes et activités", icon: "clock.arrow.circlepath", action: .showHistory,
                                  pipedrive: true)
                    historyButton("Voir les Leexi", icon: "asset:Leexi", action: .showLeexi, pipedrive: false)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isAlternate ? Color.cardAlternate : Color.cardPrimary)
                .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: Informations

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                // Société et personne sans lien à part (demande d'Yves du 11/11/2026) : toucher le bloc ouvre l'affaire.
                Text(item.organizationName ?? "Sans société")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                scoreBadge
            }
            // Personne et date sur la même ligne.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let name = item.person?.name {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Sans contact")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                dateLabel
            }
            if let ownerName {
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.circle")
                    Text("Attribuée à \(ownerName)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if let tags, !tags.isEmpty {
                tagsRow(tags)
                    .padding(.top, 2)
            }
            Text(highlighted(item.activity.subject.isEmpty ? "(sans texte)" : item.activity.subject))
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .padding(.top, 2)
        }
    }

    /// Étiquettes pleines (texte blanc), une ligne par devis, objet en gras (demandes d'Yves du 08/11/2026) :
    /// « En signature - TMA - 2j » (orange, la plus chaude), « Devis - Refonte du site - 206j » (rouge Yateo, comme
    /// le score), « 1er call à faire » (rose). Les unes sous les autres si elles ne tiennent pas sur une ligne.
    private func tagsRow(_ tags: LeadTags) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { tagViews(tags) }
            VStack(alignment: .leading, spacing: 6) { tagViews(tags) }
        }
    }

    @ViewBuilder
    private func tagViews(_ tags: LeadTags) -> some View {
        // Rendez-vous à venir en premier (demande d'Yves du 09/11/2026 : ne pas l'oublier avant de relancer).
        // Touchée : le rendez-vous dans Google Agenda (demande d'Yves du 09/11/2026).
        if let meeting = tags.meetingLine(timeZone: parisTimeZone), let next = tags.nextMeeting(timeZone: parisTimeZone) {
            Button {
                perform(.openMeeting(next))
            } label: {
                tagCapsule(Self.attributed(meeting, last: true), icon: "calendar.badge.checkmark", color: .meetingGreen)
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Ouvrir le rendez-vous dans Google Agenda")
        }
        let signing = tags.signingLines(timeZone: parisTimeZone)
        if !signing.isEmpty {
            Button {
                perform(.showQuotes)
            } label: {
                linesCapsule(signing, icon: "signature", color: .signingOrange)
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Voir les devis en signature")
        }
        let toDo = tags.toDoLines(timeZone: parisTimeZone)
        if !toDo.isEmpty {
            Button {
                perform(.showQuotes)
            } label: {
                linesCapsule(toDo, icon: "square.and.pencil", color: .toDoPurple)
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Voir les devis attendus par le client")
        }
        let quotes = tags.quoteLines(timeZone: parisTimeZone)
        if !quotes.isEmpty {
            Button {
                perform(.showQuotes)
            } label: {
                linesCapsule(quotes, icon: "doc.text.fill", color: .yateoRed)
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Voir le détail des devis envoyés")
        }
        let access = tags.accessLines(timeZone: parisTimeZone)
        if !access.isEmpty {
            Button {
                perform(.showQuotes)
            } label: {
                linesCapsule(access, icon: "key.fill", color: .accessBlue)
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Voir les accès demandés au client")
        }
        if tags.firstCallToDo {
            tagCapsule(AttributedString("1er call à faire"), icon: "phone.fill", color: .pink)
        }
    }

    /// « Devis - **Refonte du site** - 206j » (objet en gras), chevron « › » sur la dernière ligne.
    static func attributed(_ line: LeadTags.TagLine, last: Bool) -> AttributedString {
        var result = AttributedString(line.prefix + " - ")
        var title = AttributedString(line.title)
        title.font = .caption.weight(.heavy)
        result += title
        if let age = line.age { result += AttributedString(" - " + age) }
        if last { result += AttributedString("  ›") }
        return result
    }

    /// Étiquette de plusieurs devis : une ligne par devis, chacune avec sa petite icône (demande d'Yves du 08/11/2026).
    private func linesCapsule(_ lines: [LeadTags.TagLine], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: icon)
                    Text(Self.attributed(line, last: index == lines.count - 1))
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(color.gradient))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func tagCapsule(_ text: AttributedString, icon: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon)
            Text(text)
                .multilineTextAlignment(.leading)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(color.gradient))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    /// Icône + texte explicites (un Label n'affichait que l'icône dans cette ligne).
    private var dateLabel: some View {
        let status = item.activity.dateStatus(timeZone: parisTimeZone)
        let color = status?.color ?? Color.secondary
        return HStack(spacing: 4) {
            Image(systemName: "calendar")
            Text(item.activity.displayDate)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .fixedSize()
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var scoreBadge: some View {
        if let score = item.score {
            let color = ScoreBand(score: score).color
            Text(FrenchFormat.number(score, maxDecimals: 1))
                .font(.system(.subheadline, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
                )
                .shadow(color: color.opacity(0.35), radius: 4, x: 0, y: 2)
                .accessibilityLabel("Score \(FrenchFormat.number(score, maxDecimals: 1))")
        } else {
            Text("—")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Sans score")
        }
    }

    // MARK: Raisons des boutons grisés

    private var busyReason: String? {
        isBusy ? "Un enregistrement est en cours pour cette activité, patientez une seconde." : nil
    }

    private var phoneReason: String? {
        item.phoneNumbers.isEmpty ? "Aucun numéro de téléphone pour ce contact dans Pipedrive." : nil
    }

    private var whatsappReason: String? {
        if !whatsappInstalled { return "WhatsApp n'est pas installé sur cet iPhone." }
        if item.phoneNumbers.isEmpty { return "Aucun numéro de téléphone pour ce contact dans Pipedrive." }
        if item.mobileNumbers.isEmpty {
            return "Ce contact n'a que des numéros fixes (01 à 05, 08, 09) : WhatsApp n'est possible qu'avec un mobile."
        }
        return nil
    }

    private var emailReason: String? {
        item.emailAddresses.isEmpty ? "Aucune adresse e-mail pour ce contact dans Pipedrive." : nil
    }

    private var personReason: String? {
        item.person == nil && item.activity.personID == nil ? "Aucun contact n'est lié à cette activité." : nil
    }

    // MARK: Boutons

    /// Ligne de boutons dans un conteneur arrondi très léger, teinté de la couleur de la ligne ;
    /// fond gris quand aucun bouton de la ligne n'est utilisable (ex. contact sans numéro).
    private func buttonRow<Content: View>(_ style: ButtonRowStyle, unavailable: Bool,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 2) {
            content()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(unavailable ? Color.gray.opacity(0.2) : style.color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.gray.opacity(unavailable ? 0.3 : 0), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: unavailable)
    }

    /// Bouton façon app Contacts : pastille ronde (pleine pour les actions, teintée pour l'historique),
    /// libellé dessous ; grisé = touche possible pour savoir pourquoi ; logo Pipedrive discret dans le coin.
    private func chip(_ title: String, icon: String, action: ActivityAction, row: ButtonRowStyle,
                      disabledReason: String?, pipedrive: Bool = false) -> some View {
        let enabled = disabledReason == nil
        let color = enabled ? row.color : Color.gray
        return Button {
            if let disabledReason {
                perform(.explain(disabledReason))
            } else {
                perform(action)
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    if row.isFilled {
                        Circle()
                            .fill(LinearGradient(colors: [color.opacity(0.8), color], startPoint: .top, endPoint: .bottom))
                            .shadow(color: color.opacity(enabled ? 0.35 : 0), radius: 5, x: 0, y: 3)
                    } else {
                        Circle()
                            .fill(color.opacity(0.14))
                            .overlay(Circle().strokeBorder(color.opacity(0.25), lineWidth: 1))
                    }
                    chipIcon(icon, color: row.isFilled ? .white : color)
                }
                .frame(width: 40, height: 40)
                .overlay(alignment: .topTrailing) {
                    if pipedrive { PipedriveBadge(color: color).offset(x: 4, y: -3) }
                }
                Text(title)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(enabled ? 0.8 : 0.4))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(height: 26, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
        .accessibilityHint(disabledReason ?? (pipedrive ? "Enregistre une activité dans Pipedrive" : ""))
    }

    /// Symbole système, ou image du catalogue (« asset:WhatsApp » = vraie icône WhatsApp), dans la couleur de la ligne.
    @ViewBuilder
    private func chipIcon(_ icon: String, color: Color) -> some View {
        if icon.hasPrefix("asset:") {
            // Forme de l'icône (WhatsApp) teintée comme les autres boutons de la ligne.
            Image(String(icon.dropFirst("asset:".count)))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(color)
        } else {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    /// Bouton d'historique : capsule avec pastille d'icône, texte et chevron.
    private func historyButton(_ title: String, icon: String, action: ActivityAction, pipedrive: Bool) -> some View {
        let color = ButtonRowStyle.history.color
        return Button {
            perform(action)
        } label: {
            HStack(spacing: 8) {
                GlyphIcon(name: icon, size: 15)
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(color.opacity(0.14)))
                    .overlay(alignment: .topTrailing) {
                        if pipedrive { PipedriveBadge(color: color).offset(x: 4, y: -3) }
                    }
                Text(title)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(color.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Symbole système, ou logo du catalogue (« asset:Leexi », « asset:OnOff », « asset:WhatsApp ») teinté
/// comme le texte environnant.
struct GlyphIcon: View {
    let name: String
    let size: CGFloat

    var body: some View {
        if name.hasPrefix("asset:") {
            Image(String(name.dropFirst("asset:".count)))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
        }
    }
}

/// Texte avec les mots clés (signer, devis, contrat, accès… et les mots du métier qui suivent) en gras orange.
func highlighted(_ text: String) -> AttributedString {
    var attributed = AttributedString(text)
    let keywordColor: Color = .keywordOrange
    for range in KeywordHighlight.ranges(in: text) {
        if let attributedRange = Range(range, in: attributed) {
            attributed[attributedRange].inlinePresentationIntent = .stronglyEmphasized
            attributed[attributedRange].foregroundColor = keywordColor
        }
    }
    return attributed
}

/// Petit logo Pipedrive discret (« p » dans la couleur de l'icône) : ce bouton agit sur Pipedrive.
struct PipedriveBadge: View {
    let color: Color

    var body: some View {
        Text("p")
            .font(.system(size: 8, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .offset(y: -0.5)
            .frame(width: 13, height: 13)
            .background(Circle().fill(Color.cardPrimary))
            .overlay(Circle().strokeBorder(color.opacity(0.6), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Effet d'appui discret (léger enfoncement) pour toutes les tuiles.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Carte d'historique : barre de couleur à gauche, pastille du type, date, titre, texte.
struct HistoryCard: View {
    let color: Color
    let icon: String
    /// Deuxième icône, juste à côté de la première (« Répondeur + Msg vocal » : téléphone barré + bande).
    var secondIcon: String? = nil
    let badge: String
    let date: String
    let title: String?
    let text: String
    let footer: String?
    var lineLimit: Int? = nil
    var link: URL?
    /// Logo de l'outil d'appel (« asset:Aircall », « asset:OnOff ») après le titre, sur la même ligne.
    var channelIcon: String? = nil
    /// Journal automatique (répondeur, appel décroché) : 2 lignes seulement.
    var compact = false
    /// Carte pliable (texte long) : plié = 3 lignes, déplié = tout.
    var isCollapsible = false
    var isExpanded = true
    var onToggle: (() -> Void)?

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
                .contentShape(Rectangle())
                .onTapGesture {
                    if isCollapsible { onToggle?() }
                }
        }
    }

    /// Texte assez long pour mériter d'être plié.
    static func isLong(_ text: String) -> Bool {
        text.count > 180 || text.split(separator: "\n", omittingEmptySubsequences: false).count > 4
    }

    /// Ligne 1 : type + date ; ligne 2 : « Appel sortant décroché · Durée 2 min 15 s ».
    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            badgeLine
            HStack(spacing: 5) {
                Text([title, text.isEmpty ? nil : text].compactMap { $0 }.joined(separator: " · "))
                    .lineLimit(1)
                if let channelIcon {
                    GlyphIcon(name: channelIcon, size: 12)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.05))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(color.opacity(0.6))
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var badgeLine: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                GlyphIcon(name: icon, size: 11)
                if let secondIcon {
                    GlyphIcon(name: secondIcon, size: 11)
                }
                Text(badge)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            Text(date)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// Commentaire complet, en texte plus gros (c'est l'information importante).
    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                badgeLine
                if isCollapsible {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                        .accessibilityLabel(isExpanded ? "Replier" : "Déplier")
                }
            }
            if let title {
                // Même taille que le texte en dessous ; logo de l'outil d'appel juste après.
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    if let channelIcon {
                        GlyphIcon(name: channelIcon, size: 15)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text(highlighted(text))
                .font(.body)
                .lineLimit(isCollapsible && !isExpanded ? 3 : lineLimit)
                .fixedSize(horizontal: false, vertical: true)
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let link {
                Link(destination: link) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Ouvrir dans Leexi")
                    }
                    .font(.caption.weight(.semibold))
                }
                .tint(color)
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(color)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension HistoryChannel {
    /// Logo (masque teinté) : Aircall ou OnOff.
    var icon: String {
        switch self {
        case .aircall: return "asset:Aircall"
        case .onoff: return "asset:OnOff"
        }
    }
}

extension HistoryKind {
    var color: Color {
        switch self {
        case .note: return .orange
        case .call: return .green
        case .voicemail: return .red
        case .message: return .teal
        case .mail: return .blue
        case .meeting: return .indigo
        case .task: return .gray
        case .other: return .brown
        }
    }

    var icon: String {
        switch self {
        case .note: return "note.text"
        case .call: return "phone.fill"
        case .voicemail: return "asset:Repondeur"
        case .message: return "message.fill"
        case .mail: return "envelope.fill"
        case .meeting: return "calendar"
        case .task: return "checkmark.circle"
        case .other: return "circle.fill"
        }
    }
}

extension ScoreBand {
    /// Bleu (< 20, peu important) → sarcelle → orange → rouge (≥ 60, important).
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
    /// Rouge en retard, orange aujourd'hui, vert à venir.
    var color: Color {
        switch self {
        case .overdue: return .yateoRed // même rouge que le nom de la société
        case .today: return .orange
        case .upcoming: return .green
        }
    }
}

extension Color {
    /// Bleu clair des lignes de boutons alternées.
    static let lightBlue = Color(red: 0.33, green: 0.67, blue: 1.0)
    /// Rouge Yateo (lettres « CRM » du logo) : société, date en retard, score élevé.
    static let yateoRed = Color("YateoRed")
    static let appBackground = Color("AppBackground")
    static let cardPrimary = Color("CardPrimary")
    static let cardAlternate = Color("CardAlternate")
    static let pipedriveGreen = Color("PipedriveGreen")
    /// Orange des mots clés mis en évidence (même orange que la ligne Mails, lisible en texte).
    static let keywordOrange = Color(red: 0.93, green: 0.42, blue: 0.16)
    /// Étiquette « En signature » : orange vif, plus chaud que le violet « Devis envoyé ».
    static let signingOrange = Color(red: 0.96, green: 0.36, blue: 0.0)
    /// Étiquette « Accès » (accès demandés au client, pas encore reçus).
    static let accessBlue = Color(red: 0.05, green: 0.42, blue: 0.85)
    /// Étiquette « Devis à faire » (le client attend un devis pas encore envoyé).
    static let toDoPurple = Color(red: 0.50, green: 0.22, blue: 0.84)
    /// Étiquette « RDV à venir » (rendez-vous déjà calé avec le contact).
    static let meetingGreen = Color(red: 0.10, green: 0.60, blue: 0.36)
}

/// Couleurs des 4 lignes (demande d'Yves du 07/11/2026) : actions en orange (appels, mails),
/// historique en bleu (alertes enregistrées dans Pipedrive, notes / Leexi).
enum ButtonRowStyle {
    case contact, mails, alerts, history

    var color: Color {
        switch self {
        case .contact: return .orange
        case .mails: return Color(red: 0.93, green: 0.42, blue: 0.16)
        case .alerts: return .blue
        case .history: return .lightBlue
        }
    }

    /// Pastille pleine pour les actions, teintée pour l'historique.
    var isFilled: Bool { self == .contact || self == .mails }
}
