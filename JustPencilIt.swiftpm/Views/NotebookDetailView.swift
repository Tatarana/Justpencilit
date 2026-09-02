import SwiftUI
import PencilKit

/// Tela de um caderno aberto: mostra o canvas de desenho da Apple Pencil.
struct NotebookDetailView: View {
    let title: String
    @Binding var drawing: PKDrawing

    var body: some View {
        CanvasView(drawing: $drawing)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .ignoresSafeArea(.container, edges: .bottom)
    }
}
