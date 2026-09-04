import SwiftUI
import PencilKit

/// Uma página dentro do carrossel: carrega o desenho do disco ao aparecer e
/// salva a cada mudança (e ao sair, como rede de segurança). Renderizada como
/// uma folha "flutuando" sobre uma mesa, com sombra e furos perfurados perto
/// da borda esquerda — pra parecer mais com um caderno físico de verdade.
struct NotebookPageCanvas: View {
    // Modo canhoto (tela de Ajustes): espelha os furos perfurados pra borda
    // direita, já que a margem/traço vermelho já é espelhado no CanvasView.
    @AppStorage(AppSettingsKeys.leftHandedMode) private var isLeftHanded: Bool = false

    @Bindable var page: NotebookPage
    let background: PageBackground
    var isActive: Bool = true
    var penKind: PenKind = .pen
    var penColor: PenColor = .black
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }

    // Disparados de fora (menu do caderno) pra suavizar os traços da página
    // atual, desfazer, ou refazer a última mudança desfeita — incrementar o
    // número é o sinal, o valor em si não importa.
    var smoothTrigger: Int = 0
    var undoTrigger: Int = 0
    var redoTrigger: Int = 0
    // Quantos passos dá pra desfazer/refazer agora (0...maxUndoSlots) — a UI
    // usa isso pra habilitar/desabilitar os botões e mostrar um contador.
    @Binding var undoCount: Int
    @Binding var redoCount: Int

    // Até 20 "fotos" do desenho, uma por mudança (cada traço novo, cada
    // apagão, cada suavização) — desfazer sempre volta uma de cada vez, da
    // mais recente pra mais antiga. Passar de 20 descarta a mais antiga (a
    // de baixo da pilha), como todo undo com memória limitada.
    private static let maxUndoSlots = 20

    @State private var drawing = PKDrawing()
    @State private var undoStack: [PKDrawing] = []
    // Pilha espelhada do undoStack: cada Desfazer empilha aqui o desenho de
    // ANTES de desfazer, pra "Refazer" poder trazer de volta. Qualquer
    // mudança nova de verdade (um traço, um apagão, uma suavização) zera
    // essa pilha — igual todo undo/redo, uma vez que se segue um caminho
    // novo, o "futuro" antigo deixa de fazer sentido.
    @State private var redoStack: [PKDrawing] = []
    // Verdadeiro só durante a própria troca de `drawing` feita por
    // applySmoothing()/performUndo() — usado pra distinguir "o usuário
    // desenhou algo novo" de "nós mesmos trocamos o desenho", já que os
    // dois disparam o mesmo onChange(of: drawing).
    @State private var isInternalDrawingUpdate = false
    // Incrementado a cada Desfazer/Suavizar e usado como `.id()` do
    // CanvasView logo abaixo — força o SwiftUI a JOGAR FORA o PKCanvasView
    // atual e criar um novo do zero (ver makeUIView) sempre que a gente
    // troca o desenho por fora. Só reatribuir `drawing` não bastava: o
    // PKCanvasView guarda por baixo dos panos seu próprio histórico/estado
    // de traço (previsão de tinta, undo manager nativo etc.), e esse estado
    // interno não é resetado só por causa de uma nova atribuição a
    // `.drawing` — daí os traços "desfeitos" voltando sozinhos ao desenhar
    // de novo. Recriar a view do zero elimina esse estado por completo.
    @State private var canvasGeneration = 0
    // Trava de segurança: quando um Desfazer for derrubar uma fatia grande
    // do que está escrito de uma vez só (o sintoma de um bug catastrófico,
    // como o que apagou uma página inteira por engano), a gente PARA e
    // pede confirmação em vez de aplicar direto — undo não deveria
    // conseguir sumir com dias de anotações sem avisar.
    @State private var isConfirmingBigUndo = false
    @State private var pendingUndoSnapshot: PKDrawing?

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
                holeInset: holeInset,
                isLeftHanded: isLeftHanded
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
                .id(canvasGeneration)
                .clipShape(pageShape, style: FillStyle(eoFill: true))
                .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 8)
                .frame(width: cardSize.width, height: cardSize.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
        .onAppear(perform: load)
        .onChange(of: drawing) { oldValue, newValue in
            save(newValue)
            // Se a mudança veio do próprio usuário (um traço novo, um
            // apagão) — não de nós mesmos desfazendo/suavizando — guarda
            // como era ANTES dessa mudança, pra "Desfazer" poder voltar
            // pra lá depois.
            if isInternalDrawingUpdate {
                isInternalDrawingUpdate = false
            } else {
                pushUndoSnapshot(oldValue)
                clearRedoStack()
            }
        }
        .onChange(of: smoothTrigger) { _, _ in applySmoothing() }
        .onChange(of: undoTrigger) { _, _ in performUndo() }
        .onChange(of: redoTrigger) { _, _ in performRedo() }
        .onDisappear {
            save(drawing)
            // "Debounce" natural: como esta view é recriada por página (ver
            // `.id(page.id)` em PageCarouselView), sair da página SEMPRE
            // dispara isso — momento ideal pra rodar o OCR, já que a pessoa
            // acabou de parar de escrever nela.
            triggerOCRIfNeeded()
        }
        .alert(
            "Desfazer vai apagar bastante coisa",
            isPresented: $isConfirmingBigUndo,
            presenting: pendingUndoSnapshot
        ) { snapshot in
            Button("Cancelar", role: .cancel) { pendingUndoSnapshot = nil }
            Button("Desfazer mesmo assim", role: .destructive) {
                applyUndo(snapshot)
                pendingUndoSnapshot = nil
            }
        } message: { _ in
            Text("Essa ação vai remover a maior parte do que está escrito nesta página. Tem certeza?")
        }
    }

    private func load() {
        // Marca como "mudança nossa" — sem isso, trocar `drawing` do valor
        // inicial vazio pro conteúdo carregado do disco dispara o mesmo
        // onChange(of: drawing) de qualquer edição do usuário, que empilha
        // o valor ANTERIOR (vazio!) na memória de desfazer. Resultado: a
        // página abre com "1 passo pra desfazer" disponível, e esse passo
        // é voltar pro vazio — foi exatamente isso que apagou uma página
        // inteira com um único toque em Desfazer. Este é o bug crítico
        // relatado e corrigido.
        isInternalDrawingUpdate = true
        drawing = DrawingStore.load(fileName: page.drawingFileName)
        // A memória de desfazer/refazer é só desta visita à página — não
        // persiste em disco, então sai e volta zerada, como na maioria dos
        // apps de desenho.
        undoStack.removeAll()
        undoCount = 0
        clearRedoStack()
    }

    private func save(_ drawing: PKDrawing) {
        DrawingStore.save(drawing, fileName: page.drawingFileName)
        page.updatedAt = Date()
        page.ocrDirty = true
    }

    /// Roda o OCR desta página em segundo plano, se ela tiver algo pendente.
    /// Se o app for fechado antes disso terminar, a varredura de páginas
    /// pendentes (ver OCRService.catchUpSweep) pega ela na próxima abertura.
    private func triggerOCRIfNeeded() {
        guard page.ocrDirty else { return }
        let pageRef = page
        Task {
            await OCRService.process(pageRef)
        }
    }

    private func applySmoothing() {
        pushUndoSnapshot(drawing)
        clearRedoStack()
        isInternalDrawingUpdate = true
        drawing = HandwritingSmoothing.smoothed(drawing, level: .medium)
        canvasGeneration += 1
    }

    /// Guarda uma "foto" do desenho pra poder voltar a ela depois — usada
    /// tanto por traços/apagões normais quanto pela suavização, então
    /// "Desfazer" reverte a última mudança de qualquer tipo, na ordem certa.
    private func pushUndoSnapshot(_ snapshot: PKDrawing) {
        undoStack.append(snapshot)
        if undoStack.count > Self.maxUndoSlots {
            undoStack.removeFirst()
        }
        undoCount = undoStack.count
    }

    private func pushRedoSnapshot(_ snapshot: PKDrawing) {
        redoStack.append(snapshot)
        if redoStack.count > Self.maxUndoSlots {
            redoStack.removeFirst()
        }
        redoCount = redoStack.count
    }

    private func clearRedoStack() {
        redoStack.removeAll()
        redoCount = 0
    }

    private func performUndo() {
        guard let previous = undoStack.last else { return }

        // Trava de segurança: se o passo de desfazer for reduzir drasticamente
        // a quantidade de traços da página (ex: ia sobrar 1/4 ou menos do
        // que tem agora, ou nada) numa página que já tinha bastante coisa,
        // isso tem cara de desastre (bug ou toque sem querer), não de uma
        // correção pontual — para e confirma antes de aplicar.
        let currentCount = drawing.strokes.count
        let previousCount = previous.strokes.count
        let isCatastrophic = currentCount >= 8 && previousCount <= max(1, currentCount / 4)

        if isCatastrophic {
            pendingUndoSnapshot = previous
            isConfirmingBigUndo = true
        } else {
            applyUndo(previous)
        }
    }

    /// Efetivamente aplica um passo de desfazer já decidido (direto, ou
    /// confirmado no alerta de segurança) — remove do topo da pilha, guarda
    /// o desenho atual pra "Refazer" poder trazer de volta, e troca o
    /// desenho exibido.
    private func applyUndo(_ snapshot: PKDrawing) {
        guard !undoStack.isEmpty else { return }
        undoStack.removeLast()
        pushRedoSnapshot(drawing)
        isInternalDrawingUpdate = true
        drawing = snapshot
        undoCount = undoStack.count
        canvasGeneration += 1
    }

    /// Reverte um Desfazer: volta pro desenho de antes dele, e guarda o
    /// atual de volta na pilha de desfazer — como um Desfazer normal, só
    /// que no sentido contrário.
    private func performRedo() {
        guard let next = redoStack.popLast() else { return }
        pushUndoSnapshot(drawing)
        isInternalDrawingUpdate = true
        drawing = next
        redoCount = redoStack.count
        canvasGeneration += 1
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
    var isLeftHanded: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius)
        for center in holeCenters(in: rect, spacing: holeSpacing, inset: holeInset, isLeftHanded: isLeftHanded) {
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

private func holeCenters(in rect: CGRect, spacing: CGFloat, inset: CGFloat, isLeftHanded: Bool = false) -> [CGPoint] {
    guard rect.height > 0 else { return [] }
    let count = max(Int(rect.height / spacing), 1)
    let totalHeight = CGFloat(count - 1) * spacing
    let startY = rect.minY + (rect.height - totalHeight) / 2
    // Modo canhoto: os furos vão pra borda direita, então a mão que escreve
    // (a esquerda) nunca fica em cima deles — como um caderno de espiral
    // "invertido" de verdade.
    let x = isLeftHanded ? rect.maxX - inset : rect.minX + inset
    return (0..<count).map { i in
        CGPoint(x: x, y: startY + CGFloat(i) * spacing)
    }
}

