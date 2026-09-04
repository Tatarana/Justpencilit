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

    // Espessura de caneta/marcador — pertence à tela de Ajustes (mesma
    // chave, ver AppSettingsKeys em SettingsView.swift), mas fica também
    // acessível aqui, na hora do uso: segurar o dedo na ferramenta abre um
    // slider rápido, sem precisar sair do caderno pra ajustar.
    @AppStorage(AppSettingsKeys.penStrokeWidth) private var penWidthMultiplier: Double = 1.0
    @AppStorage(AppSettingsKeys.markerStrokeWidth) private var markerWidthMultiplier: Double = 1.0
    @State private var widthPopoverKind: PenKind?

    private let widthRange: ClosedRange<Double> = 0.5...2.0

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
                    // Só caneta e marcador têm espessura ajustável — a
                    // borracha usa sempre o modo vetorial do PencilKit.
                    // Segurar o dedo na ferramenta (já selecionada ou não)
                    // abre um slider rápido, sem sair do caderno.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                            guard option != .eraser else { return }
                            kind = option
                            widthPopoverKind = option
                        }
                    )
                    .popover(item: Binding(
                        get: { widthPopoverKind == option ? option : nil },
                        set: { widthPopoverKind = $0 }
                    )) { popoverKind in
                        widthPopover(for: popoverKind)
                    }
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

    @ViewBuilder
    private func widthPopover(for popoverKind: PenKind) -> some View {
        let binding: Binding<Double> = popoverKind == .marker ? $markerWidthMultiplier : $penWidthMultiplier
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Espessura — \(popoverKind.label)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int((binding.wrappedValue * 100).rounded()))%")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: binding, in: widthRange, step: 0.05)
                .frame(width: 220)
        }
        .padding(16)
        .presentationCompactAdaptation(.popover)
    }
}
