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

    // Tamanho disponível na tela (via GeometryReader do chamador). Usado pra
    // calcular uma página mais alta que a tela, com rolagem vertical — tipo
    // uma folha de caderno "comprida" de verdade.
    var canvasSize: CGSize = .zero
    var pageHeightMultiplier: CGFloat = 2.5

    // Reporta o gesto de arrastar horizontal com o dedo (pra "puxar" a
    // página e virar), sem interferir na rolagem vertical do conteúdo.
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }

    private func contentSize(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return size }
        return CGSize(width: size.width, height: size.height * pageHeightMultiplier)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.drawingPolicy = drawingPolicy
        canvasView.backgroundColor = background.makeBackgroundColor()
        // Causa raiz do "traço branco": o PencilKit adapta automaticamente
        // preto↔branco conforme o modo claro/escuro do sistema, presumindo
        // que a "tinta" deve contrastar com um fundo que também mudaria de
        // cor. Nosso papel é sempre claro (creme), então forçamos o canvas
        // a se comportar sempre como modo claro — assim a cor escolhida na
        // PenToolbar é sempre a cor que de fato aparece no papel.
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.tool = penKind.makeTool(color: penColor)
        canvasView.delegate = context.coordinator
        canvasView.isScrollEnabled = true
        canvasView.alwaysBounceVertical = true
        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 1
        let resolvedContentSize = contentSize(for: canvasSize)
        canvasView.contentSize = resolvedContentSize
        if isActive {
            canvasView.becomeFirstResponder()
        }
        context.coordinator.updateMargin(for: canvasView, background: background, contentSize: resolvedContentSize)
        context.coordinator.setUpPageTurnGesture(for: canvasView)
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Sem isso, o Coordinator continuaria chamando os closures (como
        // onDragChanged) capturados na primeira renderização — aqui
        // garantimos que ele sempre veja a versão mais recente.
        context.coordinator.parent = self

        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
        uiView.backgroundColor = background.makeBackgroundColor()
        // Reaplicado sempre — é barato, e garante que a ferramenta nunca
        // fique dessincronizada da PenToolbar (sem depender de um picker
        // externo que poderia reverter pra outra cor sozinho).
        uiView.tool = penKind.makeTool(color: penColor)
        let newContentSize = contentSize(for: canvasSize)
        if newContentSize.width > 0, uiView.contentSize != newContentSize {
            uiView.contentSize = newContentSize
        }
        context.coordinator.updateMargin(for: uiView, background: background, contentSize: uiView.contentSize)

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

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var parent: CanvasView
        private var pageTurnPan: UIPanGestureRecognizer?
        // Linha vermelha de margem (estilo pautado escolar) — rola junto com
        // o conteúdo da página, então fica embutida no canvas como subview.
        private let marginLine: UIView = {
            let view = UIView()
            view.backgroundColor = UIColor.systemRed.withAlphaComponent(0.4)
            view.isUserInteractionEnabled = false
            return view
        }()

        init(_ parent: CanvasView) {
            self.parent = parent
        }

        func updateMargin(for canvasView: PKCanvasView, background: PageBackground, contentSize: CGSize) {
            guard let marginX = background.marginX else {
                marginLine.isHidden = true
                return
            }
            if marginLine.superview !== canvasView {
                canvasView.insertSubview(marginLine, at: 0)
            }
            let height = max(contentSize.height, canvasView.bounds.height)
            marginLine.frame = CGRect(x: marginX, y: 0, width: 1.5, height: height)
            marginLine.isHidden = false
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }

        // MARK: - Gesto de "puxar" pra virar página

        /// Instala um pan gesture próprio, que só "vence" a rolagem vertical
        /// nativa do PKCanvasView quando o arrasto inicial é majoritariamente
        /// horizontal — assim dá pra rolar a página com o dedo normalmente,
        /// e também puxar de lado pra virar, sem os dois brigarem.
        func setUpPageTurnGesture(for canvasView: PKCanvasView) {
            guard pageTurnPan == nil else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePageTurnPan(_:)))
            pan.delegate = self
            pan.maximumNumberOfTouches = 1
            canvasView.addGestureRecognizer(pan)
            canvasView.panGestureRecognizer.require(toFail: pan)
            pageTurnPan = pan
        }

        @objc private func handlePageTurnPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .changed:
                parent.onDragChanged(translation.x)
            case .ended, .cancelled, .failed:
                let velocity = gesture.velocity(in: view)
                parent.onDragEnded(translation.x, velocity.x)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pageTurnPan,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            let translation = pan.translation(in: view)
            // Só assume o gesto (e bloqueia a rolagem vertical) se o
            // arrasto for claramente mais horizontal do que vertical.
            return abs(translation.x) > abs(translation.y) * 1.2 && abs(translation.x) > 6
        }
    }
}
