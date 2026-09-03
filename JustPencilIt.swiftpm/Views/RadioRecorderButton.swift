import SwiftUI

/// O gatilho pra gravar uma ideia: em vez de um botão redondo padrão (como
/// os outros ícones da tela), é desenhado como um rádio-gravador retrô de
/// verdade, no mesmo estilo mangá/quadrinho das capas dos cadernos —
/// contorno preto grosso, sombra dura, textura de pontinhos — pra parecer
/// mais um elemento vivo da cena do que um controle de UI comum. A lucezinha
/// vermelha pisca bem devagar, convidando o toque.
struct RadioRecorderButton: View {
    var action: () -> Void

    @State private var lightOn = true

    var body: some View {
        Button(action: action) {
            ZStack {
                // Sombra dura, mesmo truque das capas de caderno.
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black)
                    .offset(x: 4, y: 4)

                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.86, green: 0.27, blue: 0.21), Color(red: 0.70, green: 0.16, blue: 0.14)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(RadioHalftoneDots().opacity(0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.black, lineWidth: 3))

                VStack(spacing: 5) {
                    // Alça no topo.
                    Capsule()
                        .stroke(Color.black, lineWidth: 3)
                        .frame(width: 34, height: 14)
                        .offset(y: -30)

                    HStack(spacing: 6) {
                        RadioSpeaker()
                        // Janelinha da fita, com os dois carretéis e a
                        // lucezinha de gravação piscando.
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.75))
                                .frame(width: 30, height: 20)
                            HStack(spacing: 8) {
                                Circle().stroke(Color.white, lineWidth: 1.5).frame(width: 8, height: 8)
                                Circle().stroke(Color.white, lineWidth: 1.5).frame(width: 8, height: 8)
                            }
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                                .offset(y: -11)
                                .opacity(lightOn ? 1 : 0.25)
                        }
                        RadioSpeaker()
                    }
                }
                .padding(.top, 6)

                // Antena, saindo do canto.
                Path { path in
                    path.move(to: CGPoint(x: 30, y: -34))
                    path.addLine(to: CGPoint(x: 40, y: -54))
                }
                .stroke(Color.black, lineWidth: 2.5)
            }
            .frame(width: 78, height: 62)
            .rotationEffect(.degrees(-4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Gravar uma ideia")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                lightOn.toggle()
            }
        }
    }
}

private struct RadioSpeaker: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.black, lineWidth: 2)
            Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1).padding(4)
        }
        .frame(width: 22, height: 22)
    }
}

/// Mesma trama de meio-tom usada nas capas de caderno, só que num tamanho
/// menor de ponto (o botão é bem menor que uma capa inteira).
private struct RadioHalftoneDots: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 6
            let dotRadius: CGFloat = 0.9
            var row = 0
            var y = spacing / 2
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? spacing / 2 : spacing
                while x < size.width {
                    let rect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                    x += spacing
                }
                y += spacing * 0.87
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    RadioRecorderButton(action: {})
        .padding(60)
        .background(Color(.systemGroupedBackground))
}
