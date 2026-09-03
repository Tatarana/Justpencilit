import SwiftUI

/// Barra de ferramentas própria do app — substitui a paleta padrão do
/// sistema (PKToolPicker), que sempre inclui branco como opção de cor e
/// fazia o traço "sumir" no papel. Aqui preto é o padrão e branco
/// simplesmente não existe como escolha.
///
/// Desenhada como uma cápsula flutuante (fundo translúcido, sem largura
/// fixa) pra não ocupar uma faixa inteira da tela — o chamador só precisa
/// posicioná-la como overlay sobre a página.
struct PenToolbar: View {
    @Binding var kind: PenKind
    @Binding var color: PenColor

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(PenKind.allCases) { option in
                    Button {
                        kind = option
                    } label: {
                        Image(systemName: option.systemImage)
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle().fill(kind == option ? Color.accentColor : Color(.secondarySystemBackground))
                            )
                            .foregroundStyle(kind == option ? Color.white : Color.primary)
                    }
                    .accessibilityLabel(option.label)
                }
            }

            Divider().frame(height: 22)

            HStack(spacing: 8) {
                ForEach(PenColor.allCases) { option in
                    let isSelected = color == option && kind != .eraser
                    Button {
                        color = option
                    } label: {
                        // Um "prato" neutro atrás de cada bolinha garante
                        // contraste mesmo pra cores escuras (preto) contra
                        // uma barra de ferramentas também escura no modo dark.
                        Circle()
                            .fill(Color(.tertiarySystemBackground))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 22, height: 22)
                            )
                            .overlay(
                                Circle().strokeBorder(Color.accentColor, lineWidth: isSelected ? 2.5 : 0)
                            )
                    }
                }
            }
            .opacity(kind == .eraser ? 0.35 : 1)
            .disabled(kind == .eraser)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
    }
}
