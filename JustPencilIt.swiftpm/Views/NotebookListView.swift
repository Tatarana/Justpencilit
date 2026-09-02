import SwiftUI
import PencilKit

/// Tela inicial: lista de cadernos do usuário.
struct NotebookListView: View {
    @State private var notebooks: [Notebook] = []
    @State private var drawings: [UUID: PKDrawing] = [:]

    var body: some View {
        NavigationStack {
            List {
                ForEach(notebooks) { notebook in
                    NavigationLink(notebook.title, value: notebook.id)
                }
                .onDelete(perform: deleteNotebooks)
            }
            .navigationTitle("Meus Cadernos")
            .navigationDestination(for: UUID.self) { notebookID in
                NotebookDetailView(
                    title: title(for: notebookID),
                    drawing: drawingBinding(for: notebookID)
                )
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addNotebook) {
                        Label("Novo Caderno", systemImage: "plus")
                    }
                }
            }
            .overlay {
                if notebooks.isEmpty {
                    ContentUnavailableView(
                        "Nenhum caderno ainda",
                        systemImage: "pencil.and.outline",
                        description: Text("Toque em + para criar seu primeiro caderno.")
                    )
                }
            }
        }
    }

    private func addNotebook() {
        let notebook = Notebook(title: "Caderno \(notebooks.count + 1)")
        notebooks.append(notebook)
        drawings[notebook.id] = PKDrawing()
    }

    private func deleteNotebooks(at offsets: IndexSet) {
        for index in offsets {
            drawings.removeValue(forKey: notebooks[index].id)
        }
        notebooks.remove(atOffsets: offsets)
    }

    private func title(for id: UUID) -> String {
        notebooks.first(where: { $0.id == id })?.title ?? "Caderno"
    }

    private func drawingBinding(for id: UUID) -> Binding<PKDrawing> {
        Binding(
            get: { drawings[id, default: PKDrawing()] },
            set: { drawings[id] = $0 }
        )
    }
}

#Preview {
    NotebookListView()
}
