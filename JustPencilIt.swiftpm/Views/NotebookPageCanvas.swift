import SwiftUI
import PencilKit

/// Uma página dentro do carrossel: carrega o desenho do disco ao aparecer e
/// salva a cada mudança (e ao sair, como rede de segurança). Renderizada como
/// uma folha "flutuando" sobre uma mesa, com sombra e furos perfurados perto
/// da borda esquerda — pra parecer mais com um caderno físico de verdade.
struct NotebookPageCanvas: View {
    @Bindable var page: NotebookPage
    let background: PageBackground
    var isActive: Bool = true
    var penKind: PenKind = .pen
    var penColor: PenColor = .black
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }

    @State private var drawing = PKDrawing()

    private let outerPadding: CGFloat = 22
    private let cornerRadius: CGFloat = 12
    private let holeDiameter: CGFloat = 14
    private let holeSpacing: CGFloat = 34
    private let holeInset: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let cardSize = CGSize(
                width: max(geometry.size.width - outerPadding * 2, 0),
                height: max(geometry.size.height - outerPadding * 2, 0)
            )
            let pageShape = PunchedPageShape(
                cornerRadius: cornerRadius,
                holeDiameter: holeDiameter,
                holeSpacing: holeSpacing,
                holeInset: holeInset
            )
            CanvasView(
                drawing: $drawing,
                isActive: isActive,
                background: background,
                penKind: penKind,
                penColor: penColor,
                canvasSize: cardSize,
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded
            )
                .clipShape(pageShape, style: FillStyle(eoFill: true))
                .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 8)
                .frame(width: cardSize.width, height: cardSize.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
        .onAppear(perform: load)
        .onChange(of: drawing) { _, newValue in
            save(newValue)
        }
        .onDisappear {
            save(drawing)
        }
    }

    private func load() {
        drawing = DrawingStore.load(fileName: page.drawingFileName)
    }

    private func save(_ drawing: PKDrawing) {
        DrawingStore.save(drawing, fileName: page.drawingFileName)
        page.updatedAt = Date()
    }
}

/// A página com furos redondos perfurados perto da borda esquerda — como
/// papel de caderno de espiral arrancado de um bloco. Usada como clipShape
/// com regra even-odd: o retângulo arredondado MENOS os círculos dos furos.
private struct PunchedPageShape: Shape {
    var cornerRadius: CGFloat
    var holeDiameter: CGFloat
    var holeSpacing: CGFloat
    var holeInset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius)
        for center in holeCenters(in: rect, spacing: holeSpacing, inset: holeInset) {
            let holeRect = CGRect(
                x: center.x - holeDiameter / 2,
                y: center.y - holeDiameter / 2,
                width: holeDiameter,
                height: holeDiameter
            )
            path.addEllipse(in: holeRect)
        }
        return path
    }
}

private func holeCenters(in rect: CGRect, spacing: CGFloat, inset: CGFloat) -> [CGPoint] {
    guard rect.height > 0 else { return [] }
    let count = max(Int(rect.height / spacing), 1)
    let totalHeight = CGFloat(count - 1) * spacing
    let startY = rect.minY + (rect.height - totalHeight) / 2
    return (0..<count).map { i in
        CGPoint(x: rect.minX + inset, y: startY + CGFloat(i) * spacing)
    }
}

