import SwiftUI

/// Um caderno desenhado como capa de gibi/mangá: contorno preto grosso,
/// sombra "dura" (sem blur, só deslocada), textura de pontinhos (halftone,
/// tipo trama de impressão de quadrinho), brilho diagonal de etiqueta, e
/// uma espiral simplificada na borda esquerda.
struct NotebookCoverView: View {
    let notebook: Notebook

    /// Pequena rotação fixa por caderno (derivada do id, não muda entre
    /// renders) — dá a sensação de pilha de cadernos jogados casualmente.
    private var rotationDegrees: Double {
        let bucket = abs(notebook.id.hashValue) % 9
        return Double(bucket) - 4 // -4...4
    }

    private var sectionCountLabel: String {
        let count = notebook.sections.count
        return "\(count) \(count == 1 ? "seção" : "seções")"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Sombra dura ao estilo quadrinho — sem blur, só deslocada.
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black)
                .offset(x: 6, y: 6)

            RoundedRectangle(cornerRadius: 18)
                .fill(notebook.coverColor.color.gradient)
                .overlay(HalftoneDots().opacity(0.16).clipShape(RoundedRectangle(cornerRadius: 18)))
                .overlay(GlossyStripe().clipShape(RoundedRectangle(cornerRadius: 18)))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.black, lineWidth: 3)
                )

            SpiralEdgeDots()
                .padding(.leading, 7)
                .padding(.vertical, 16)

            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text(notebook.title)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 0, x: 1.5, y: 1.5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(sectionCountLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
        }
        .aspectRatio(0.72, contentMode: .fit)
        .rotationEffect(.degrees(rotationDegrees))
        .padding(10)
    }
}

/// Textura de pontinhos (trama de meio-tom) — o efeito clássico de
/// impressão em quadrinhos/mangá, aplicado bem sutil sobre a cor da capa.
private struct HalftoneDots: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 8
            let dotRadius: CGFloat = 1.2
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

/// Faixa diagonal de brilho, tipo etiqueta/adesivo brilhante de gibi.
private struct GlossyStripe: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            Path { path in
                path.move(to: CGPoint(x: 0, y: h * 0.06))
                path.addLine(to: CGPoint(x: w * 0.4, y: 0))
                path.addLine(to: CGPoint(x: w * 0.6, y: 0))
                path.addLine(to: CGPoint(x: w * 0.18, y: h * 0.4))
                path.closeSubpath()
            }
            .fill(Color.white.opacity(0.28))
        }
        .allowsHitTesting(false)
    }
}

/// Furinhos simplificados na borda esquerda, sugerindo a espiral de um
/// caderno de verdade — versão bem leve, só pra dar personalidade à capa.
private struct SpiralEdgeDots: View {
    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 24
            let count = max(Int(geometry.size.height / spacing), 3)
            VStack(spacing: spacing - 8) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 1.3))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 10)
        .allowsHitTesting(false)
    }
}
