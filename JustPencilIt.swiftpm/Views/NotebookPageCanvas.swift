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

    // Disparados de fora (menu do caderno) pra suavizar os traços da página
    // atual, ou desfazer a última suavização — incrementar o número é o
    // sinal, o valor em si não importa.
    var smoothTrigger: Int = 0
    var undoSmoothTrigger: Int = 0
    // Quantas suavizações dá pra desfazer agora (0...maxUndoSlots) — a UI
    // usa isso pra mostrar/esconder o botão de desfazer e, se quiser, um
    // contador.
    @Binding var undoSmoothCount: Int

    // Até 3 "fotos" do desenho, uma por suavização feita em sequência —
    // desfazer sempre volta uma de cada vez, da mais recente pra mais
    // antiga. Passar de 3 descarta a mais antiga (a de baixo da pilha).
    private static let maxUndoSlots = 3

    @State private var drawing = PKDrawing()
    @State private var preSmoothStack: [PKDrawing] = []
    // Verdadeiro só durante a própria troca de `drawing` feita por
    // applySmoothing()/undoSmoothing() — usado pra distinguir "o usuário
    // desenhou algo novo" de "nós mesmos trocamos o desenho", já que os
    // dois disparam o mesmo onChange(of: drawing).
    @State private var isInternalDrawingUpdate = false

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
            // Se a mudança veio do próprio usuário desenhando (não de nós
            // suavizando/desfazendo), qualquer suavização anterior deixa de
            // fazer sentido pra desfazer — desfazer agora apagaria o traço
            // novo junto. Some o botão de desfazer nesse caso.
            if isInternalDrawingUpdate {
                isInternalDrawingUpdate = false
            } else if !preSmoothStack.isEmpty {
                preSmoothStack.removeAll()
                undoSmoothCount = 0
            }
        }
        .onChange(of: smoothTrigger) { _, _ in applySmoothing() }
        .onChange(of: undoSmoothTrigger) { _, _ in undoSmoothing() }
        .onDisappear {
            save(drawing)
        }
    }

    private func load() {
        drawing = DrawingStore.load(fileName: page.drawingFileName)
        // Desfazer é só pra suavização feita nesta mesma visita à página.
        preSmoothStack.removeAll()
        undoSmoothCount = 0
    }

    private func save(_ drawing: PKDrawing) {
        DrawingStore.save(drawing, fileName: page.drawingFileName)
        page.updatedAt = Date()
    }

    private func applySmoothing() {
        preSmoothStack.append(drawing)
        if preSmoothStack.count > Self.maxUndoSlots {
            preSmoothStack.removeFirst()
        }
        isInternalDrawingUpdate = true
        drawing = HandwritingSmoothing.smoothed(drawing, level: .medium)
        undoSmoothCount = preSmoothStack.count
    }

    private func undoSmoothing() {
        guard let previous = preSmoothStack.popLast() else { return }
        isInternalDrawingUpdate = true
        drawing = previous
        undoSmoothCount = preSmoothStack.count
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

