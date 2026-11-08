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
struct SwipeReveal<Content: View>: View {
    let actions: [SwipeAction]
    @Binding var isOpen: Bool
    @ViewBuilder let content: Content

    @State private var drag: CGFloat = 0
    private let buttonWidth: CGFloat = 92

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
                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        Button {
                            close()
                            action.perform()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: action.icon)
                                    .font(.title3.weight(.semibold))
                                Text(action.title)
                                    .font(.caption.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(.white)
                            .frame(width: buttonWidth - 8)
                            .frame(maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(action.color.gradient))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.vertical, 6)
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
                        isOpen = isOpen ? !(dx < -40 || predicted < -120) : (dx > 60 || predicted > 160)
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
