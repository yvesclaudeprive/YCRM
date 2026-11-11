import SwiftUI

/// Bouton révélé en glissant le bloc vers la droite.
struct SwipeAction: Identifiable {
    let title: String
    let icon: String
    let color: Color
    let perform: () -> Void

    var id: String { title }
}

/// Glisser le bloc vers la droite fait apparaître des boutons à gauche (demande d'Yves du 08/11/2026) ;
/// glisser vers la gauche ou toucher le bloc referme. Seuls les gestes nettement horizontaux comptent :
/// le défilement vertical de la liste n'est pas gêné.
/// Boutons = petites pastilles rondes + libellé, en haut à gauche, façon app Mail (choix d'Yves du 11/11/2026 :
/// plus de grands boutons sur toute la hauteur) ; toute la colonne sous la pastille reste touchable.
struct SwipeReveal<Content: View>: View {
    let actions: [SwipeAction]
    @Binding var isOpen: Bool
    @ViewBuilder let content: Content

    @State private var drag: CGFloat = 0
    private let buttonWidth: CGFloat = 78
    private let pillSize: CGFloat = 52

    private var revealWidth: CGFloat { CGFloat(actions.count) * buttonWidth }

    var body: some View {
        let offset = min(max((isOpen ? revealWidth : 0) + drag, 0), revealWidth + 24)
        content
            .overlay {
                if isOpen {
                    // Bloc ouvert : un toucher le referme au lieu d'ouvrir l'affaire.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                }
            }
            .offset(x: offset)
            .background(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(actions) { action in
                        Button {
                            close()
                            action.perform()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: action.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: pillSize, height: pillSize)
                                    .background(Circle().fill(action.color.gradient))
                                    .shadow(color: action.color.opacity(0.35), radius: 6, x: 0, y: 3)
                                Text(action.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                            }
                            .padding(.top, 14)
                            .frame(width: buttonWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .opacity(offset > 12 ? 1 : 0)
                .accessibilityHidden(!isOpen)
            }
            .simultaneousGesture(dragGesture)
            .accessibilityActions {
                ForEach(actions) { action in
                    Button(action.title, action: action.perform)
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                let (dx, dy) = (value.translation.width, value.translation.height)
                guard abs(dx) > abs(dy) * 1.5 else { return }
                drag = dx
            }
            .onEnded { value in
                let (dx, dy) = (value.translation.width, value.translation.height)
                let predicted = value.predictedEndTranslation.width
                let horizontal = abs(dx) > abs(dy) * 1.5
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if horizontal {
                        isOpen = isOpen ? !(dx < -40 || predicted < -120) : (dx > 44 || predicted > 120)
                    }
                    drag = 0
                }
            }
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isOpen = false
            drag = 0
        }
    }
}
