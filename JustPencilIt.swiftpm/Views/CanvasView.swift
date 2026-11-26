import SwiftUI
import PencilKit

/// Tela de desenho/escrita de uma página, usando PencilKit para captura da Apple Pencil.
///
/// Não usamos mais o `PKToolPicker` do sistema: sua paleta de cores sempre
/// inclui branco, e era fácil acabar com um traço "invisível" no papel.
/// A ferramenta ativa (tipo + cor) agora vem de fora, via `PenToolbar`,
/// que nunca oferece branco como opção.
///
/// A entrada por dedo é reservada pra navegação (rolar a página, puxar pra
/// virar de página) — só a Apple Pencil desenha.
struct CanvasView: UIViewRepresentable {
    // Preferências da tela de Ajustes — cada view que precisa delas declara
    // seu próprio @AppStorage com a mesma chave (ver AppSettingsKeys em
    // SettingsView.swift), sem precisar passar como parâmetro por toda a
    // cadeia NotebookPageCanvas → PageCarouselView → CanvasView.
    @AppStorage(AppSettingsKeys.penStrokeWidth) private var penWidthMultiplier: Double = 1.0
    @AppStorage(AppSettingsKeys.markerStrokeWidth) private var markerWidthMultiplier: Double = 1.0
    @AppStorage(AppSettingsKeys.leftHandedMode) private var isLeftHanded: Bool = false
    // Ajustes > Ferramenta de desenho: true = paleta padrão do iPad
    // (PKToolPicker), false = nossa PenToolbar (guardada como alternativa).
    @AppStorage(AppSettingsKeys.useSystemToolPicker) private var useSystemToolPicker: Bool = true

    @Binding var drawing: PKDrawing

    // .pencilOnly: só a Pencil desenha. O dedo fica livre pra rolar a
    // página e pro gesto de "puxar" pra virar de página.
    var drawingPolicy: PKCanvasViewDrawingPolicy = .pencilOnly

    // Controla se o canvas deve segurar o foco de entrada (teclado/Pencil).
    // Precisa ficar false enquanto algum campo de texto de fora (ex: o alerta
    // de renomear) estiver aberto, senão o PKCanvasView disputa o "first
    // responder" com esse campo e o teclado externo/virtual para de funcionar.
    var isActive: Bool = true

    // Estilo de fundo da seção (liso/pautado/quadriculado).
    var background: PageBackground = .blank

    // Ferramenta ativa, controlada pela PenToolbar (fora deste view).
    var penKind: PenKind = .pen
    var penColor: PenColor = .black

    // Tamanho disponível na tela (via GeometryReader do chamador) — só
    // decide o zoom. A folha em si tem tamanho próprio (`pageSize`, em
    // pontos de "papel"), igual em portrait, landscape ou qualquer janela.
    var canvasSize: CGSize = .zero
    var pageSize: CGSize = PageGeometry.a4

    // Não usados mais (a virada agora é a nativa, ver PageCurlView) —
    // mantidos só pra não quebrar quem ainda passa esses parâmetros.
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }

    /// Zoom que faz a largura da folha caber exatamente na tela.
    private var fitScale: CGFloat {
        guard canvasSize.width > 0, pageSize.width > 0 else { return 1 }
        return canvasSize.width / pageSize.width
    }

    /// Ajusta zoom e área rolável à tela atual. O desenho fica sempre nas
    /// mesmas coordenadas de papel — girar o iPad só muda o zoom, nunca
    /// corta nada (antes a folha tinha o tamanho da tela e perdia conteúdo).
    /// Pinça com dois dedos amplia até 3× a largura da tela.
    private func layoutPage(_ canvas: PKCanvasView, coordinator: Coordinator) {
        let fit = fitScale
        canvas.minimumZoomScale = fit
        canvas.maximumZoomScale = fit * 3
        // Só volta pro "caber na largura" quando a tela muda de tamanho
        // (girar, abrir a página) — senão desfaria o zoom da pinça a cada
        // traço.
        if abs(coordinator.lastFitScale - fit) > 0.0001 {
            coordinator.lastFitScale = fit
            canvas.zoomScale = fit
        }
        let scale = canvas.zoomScale
        let scaledSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        if canvas.contentSize != scaledSize {
            canvas.contentSize = scaledSize
        }
        coordinator.updatePaper(
            for: canvas,
            background: background,
            pageSize: pageSize,
            scale: scale,
            isLeftHanded: isLeftHanded
        )
    }

    private var currentWidthMultiplier: CGFloat {
        switch penKind {
        case .pen: return CGFloat(penWidthMultiplier)
        case .marker: return CGFloat(markerWidthMultiplier)
        case .eraser: return 1.0
        }
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PageCanvasView()
        // O PencilKit mostra sozinho um menu "Selecionar Tudo | Inserir
        // Espaço" quando o dedo toca o papel — era isso que aparecia no
        // lugar de virar a página quando o toque errava os botões ‹ ›.
        // Com a nossa PenToolbar, tiramos a interação de menu de vez. Com a
        // paleta do iPad ela fica (o laço precisa dela pra copiar/apagar a
        // seleção), e a subclasse recusa as ações fora do laço.
        if !useSystemToolPicker {
            for interaction in canvasView.interactions where interaction is UIEditMenuInteraction {
                canvasView.removeInteraction(interaction)
            }
        }
        canvasView.drawing = drawing
        canvasView.drawingPolicy = drawingPolicy
        // O padrão do papel (pautado/quadriculado) agora é desenhado numa
        // folha própria que acompanha o zoom (ver Coordinator.updatePaper);
        // o fundo do canvas é só o creme liso, pra áreas fora da folha.
        canvasView.backgroundColor = PageBackground.paperColor
        // Causa raiz do "traço branco": o PencilKit adapta automaticamente
        // preto↔branco conforme o modo claro/escuro do sistema, presumindo
        // que a "tinta" deve contrastar com um fundo que também mudaria de
        // cor. Nosso papel é sempre claro (creme), então forçamos o canvas
        // a se comportar sempre como modo claro — assim a cor escolhida na
        // PenToolbar é sempre a cor que de fato aparece no papel.
        canvasView.overrideUserInterfaceStyle = .light
        applyTool(to: canvasView, coordinator: context.coordinator)
        canvasView.delegate = context.coordinator
        canvasView.isScrollEnabled = true
        canvasView.alwaysBounceVertical = true
        canvasView.bouncesZoom = false
        layoutPage(canvasView, coordinator: context.coordinator)
        if isActive {
            canvasView.becomeFirstResponder()
        }
        canvasView.undoManager?.removeAllActions()
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Sem isso, o Coordinator continuaria chamando os closures (como
        // onDragChanged) capturados na primeira renderização — aqui
        // garantimos que ele sempre veja a versão mais recente.
        context.coordinator.parent = self

        if uiView.drawing != drawing {
            uiView.drawing = drawing
            // O PencilKit registra sozinho uma ação no SEU PRÓPRIO undo
            // manager (nativo do UIKit) a cada traço — sem saber que a gente
            // já tem um sistema de undo próprio. Se deixarmos isso acumular,
            // um gesto do sistema (3 dedos deslizando, por exemplo) aciona
            // ESSE undo manager nativo por baixo dos panos e devolve de
            // supetão traços que a gente já tinha "desfeito" pela nossa
            // pilha — exatamente o bug relatado. Como o nosso `undoStack` é
            // a única fonte de verdade, zeramos o manager nativo sempre que
            // trocamos o desenho de fora (undo/suavizar/carregar página).
            uiView.undoManager?.removeAllActions()
        }
        // Reaplicado sempre — é barato, e garante que a ferramenta nunca
        // fique dessincronizada da PenToolbar (sem depender de um picker
        // externo que poderia reverter pra outra cor sozinho). Também
        // reaplica a espessura, pra refletir na hora qualquer ajuste feito
        // na tela de Ajustes enquanto o app está aberto.
        applyTool(to: uiView, coordinator: context.coordinator)
        layoutPage(uiView, coordinator: context.coordinator)

        if isActive {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Liga o papel à ferramenta escolhida nos Ajustes: a paleta padrão do
    /// iPad (compartilhada entre todas as páginas, então a caneta/cor
    /// escolhida continua a mesma ao virar a folha) ou a nossa PenToolbar.
    private func applyTool(to canvas: PKCanvasView, coordinator: Coordinator) {
        let picker = SystemToolPicker.shared
        if useSystemToolPicker {
            if !coordinator.isObservingPicker {
                picker.addObserver(canvas)
                coordinator.isObservingPicker = true
                canvas.tool = picker.selectedTool
            }
            picker.setVisible(isActive, forFirstResponder: canvas)
        } else {
            if coordinator.isObservingPicker {
                picker.setVisible(false, forFirstResponder: canvas)
                picker.removeObserver(canvas)
                coordinator.isObservingPicker = false
            }
            canvas.tool = penKind.makeTool(color: penColor, widthMultiplier: currentWidthMultiplier)
        }
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        guard coordinator.isObservingPicker else { return }
        SystemToolPicker.shared.setVisible(false, forFirstResponder: uiView)
        SystemToolPicker.shared.removeObserver(uiView)
        coordinator.isObservingPicker = false
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        var isObservingPicker = false
        var lastFitScale: CGFloat = 0
        // A folha de papel (padrão pautado/quadriculado + margem vermelha),
        // em coordenadas de papel e escalada junto com o zoom — assim as
        // linhas ficam sempre no mesmo lugar em relação ao que foi escrito.
        private let paperView: UIView = {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.layer.anchorPoint = .zero
            return view
        }()
        private let marginLine: UIView = {
            let view = UIView()
            view.backgroundColor = UIColor.systemRed.withAlphaComponent(0.4)
            view.isUserInteractionEnabled = false
            return view
        }()

        init(_ parent: CanvasView) {
            self.parent = parent
        }

        func updatePaper(for canvasView: PKCanvasView, background: PageBackground, pageSize: CGSize, scale: CGFloat, isLeftHanded: Bool) {
            if paperView.superview !== canvasView {
                canvasView.insertSubview(paperView, at: 0)
                paperView.addSubview(marginLine)
            }
            paperView.transform = .identity
            paperView.bounds = CGRect(origin: .zero, size: pageSize)
            paperView.layer.position = .zero
            paperView.transform = CGAffineTransform(scaleX: scale, y: scale)
            paperView.backgroundColor = background.makeBackgroundColor()

            if let marginX = background.marginX {
                // Modo canhoto: espelha a margem pro lado direito da página,
                // pra não ficar embaixo da mão de quem escreve com a esquerda.
                let x = isLeftHanded ? pageSize.width - marginX : marginX
                marginLine.frame = CGRect(x: x, y: 0, width: 1.5, height: pageSize.height)
                marginLine.isHidden = false
            } else {
                marginLine.isHidden = true
            }
        }

        /// Durante a pinça: a área rolável e o papel acompanham o zoom.
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let canvas = scrollView as? PKCanvasView else { return }
            let page = parent.pageSize
            let scale = canvas.zoomScale
            canvas.contentSize = CGSize(width: page.width * scale, height: page.height * scale)
            updatePaper(
                for: canvas,
                background: parent.background,
                pageSize: page,
                scale: scale,
                isLeftHanded: parent.isLeftHanded
            )
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            // Mesmo motivo do updateUIView: zera aqui também, a cada traço
            // novo do próprio usuário, pra nunca deixar o undo manager
            // nativo do PencilKit acumular ações que ele "acha" que ainda
            // pode desfazer/refazer por conta própria.
            canvasView.undoManager?.removeAllActions()
        }
    }
}

/// PKCanvasView que nunca oferece as ações do menu de edição do PencilKit
/// ("Selecionar Tudo", "Inserir Espaço", colar...) — sem nenhuma ação
/// disponível, o sistema nem chega a abrir o menu.
final class PageCanvasView: PKCanvasView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Com o laço da paleta do iPad, deixa o menu da seleção funcionar
        // (copiar, apagar, duplicar...). Fora dele, nenhum menu.
        if tool is PKLassoTool {
            return super.canPerformAction(action, withSender: sender)
        }
        return false
    }

    private var isWiredToPageCurl = false

    /// A virada de página (PageCurlView) tem seu próprio gesto de puxar a
    /// folha. Sem isso, a rolagem vertical do papel "roubava" o dedo e a
    /// folha não virava: aqui a rolagem espera o gesto de virar desistir
    /// (arrasto mais vertical) antes de começar.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !isWiredToPageCurl else { return }
        var ancestor = superview
        while let view = ancestor {
            if view.next is UIPageViewController {
                for recognizer in view.gestureRecognizers ?? [] where recognizer is UIPanGestureRecognizer {
                    panGestureRecognizer.require(toFail: recognizer)
                }
                isWiredToPageCurl = true
                return
            }
            ancestor = view.superview
        }
    }
}

/// Uma única paleta padrão do iPad pra todas as páginas — assim a
/// ferramenta/cor escolhida não reseta ao virar a folha.
@MainActor
enum SystemToolPicker {
    static let shared: PKToolPicker = {
        let picker = PKToolPicker()
        // O papel é sempre claro: as cores da paleta valem como são, sem o
        // iOS inverter preto↔branco no modo escuro.
        picker.colorUserInterfaceStyle = .light
        return picker
    }()
}

/// Tamanho da folha, em pontos de "papel" — independente da tela.
enum PageGeometry {
    /// Largura de referência: mais ou menos a da folha em portrait num
    /// iPad de 11", então em portrait a letra fica quase em tamanho natural.
    static let width: CGFloat = 800
    /// Proporção A4 (1 : √2).
    static let a4 = CGSize(width: width, height: (width * 2.0.squareRoot()).rounded())

    /// Folha A4, alargada/alongada só se um desenho antigo (feito quando a
    /// folha tinha o tamanho da tela) passar dela — nada fica de fora.
    static func size(fitting drawing: PKDrawing) -> CGSize {
        let bounds = drawing.bounds
        guard !bounds.isNull, !bounds.isEmpty else { return a4 }
        return CGSize(
            width: max(a4.width, (bounds.maxX + 24).rounded(.up)),
            height: max(a4.height, (bounds.maxY + 48).rounded(.up))
        )
    }
}
