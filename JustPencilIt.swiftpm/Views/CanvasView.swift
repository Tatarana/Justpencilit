import SwiftUI
import PencilKit

/// Tela de desenho/escrita de uma página, usando PencilKit para captura da Apple Pencil.
struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    // .anyInput aceita dedo e Pencil (bom pra testar sem Pencil em mãos).
    // Troque para .pencilOnly quando for validar rejeição de palma no produto final.
    var drawingPolicy: PKCanvasViewDrawingPolicy = .anyInput

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.drawingPolicy = drawingPolicy
        canvasView.backgroundColor = .systemBackground
        canvasView.delegate = context.coordinator
        canvasView.becomeFirstResponder()
        context.coordinator.setUpToolPicker(for: canvasView)
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
        // Se a tool picker não estava disponível em makeUIView (janela ainda não
        // anexada), tenta de novo aqui — é seguro chamar mais de uma vez.
        context.coordinator.setUpToolPicker(for: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: CanvasView
        private var toolPicker: PKToolPicker?

        init(_ parent: CanvasView) {
            self.parent = parent
        }

        func setUpToolPicker(for canvasView: PKCanvasView) {
            guard toolPicker == nil, canvasView.window != nil else { return }
            let toolPicker = PKToolPicker()
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            toolPicker.addObserver(canvasView)
            canvasView.becomeFirstResponder()
            self.toolPicker = toolPicker
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
