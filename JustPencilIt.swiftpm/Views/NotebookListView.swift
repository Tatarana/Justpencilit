import SwiftUI
import SwiftData

/// Tela inicial: os cadernos do usuário como uma "estante" de capas de
/// gibi/mangá — grade colorida, contorno grosso, sombra dura, em vez de
/// uma lista de texto simples.
struct NotebookListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Notebook.updatedAt, order: .reverse) private var notebooks: [Notebook]

    @State private var renamingNotebook: Notebook?
    @State private var editingColorNotebook: Notebook?
    @State private var deletingNotebook: Notebook?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 4)]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    header

                    if notebooks.isEmpty {
                        ContentUnavailableView(
                            "Nenhum caderno ainda",
                            systemImage: "pencil.and.outline",
                            description: Text("Toque no + para criar seu primeiro caderno.")
                        )
                        .padding(.top, 60)
                    } else {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(notebooks) { notebook in
                                notebookCell(for: notebook)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 90)
                    }
                }

                addButton
                    .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { notebookID in
                if let notebook = notebooks.first(where: { $0.id == notebookID }) {
                    NotebookDetailView(notebook: notebook)
                }
            }
            .sheet(item: $renamingNotebook) { notebook in
                RenameSheet(originalTitle: notebook.title) { newTitle in
                    notebook.title = newTitle
                    notebook.updatedAt = Date()
                }
            }
            .confirmationDialog(
                "Cor da capa",
                isPresented: Binding(
                    get: { editingColorNotebook != nil },
                    set: { isPresented in
                        if !isPresented { editingColorNotebook = nil }
                    }
                ),
                titleVisibility: .visible
            ) {
                ForEach(NotebookColor.allCases) { option in
                    Button(option.label) {
                        editingColorNotebook?.coverColor = option
                        editingColorNotebook = nil
                    }
                }
            }
            .alert(
                "Excluir \"\(deletingNotebook?.title ?? "")\"?",
                isPresented: Binding(
                    get: { deletingNotebook != nil },
                    set: { isPresented in
                        if !isPresented { deletingNotebook = nil }
                    }
                )
            ) {
                Button("Cancelar", role: .cancel) { deletingNotebook = nil }
                Button("Excluir", role: .destructive) {
                    if let notebook = deletingNotebook {
                        delete(notebook)
                    }
                    deletingNotebook = nil
                }
            } message: {
                Text("Isso apaga todas as seções e páginas desse caderno. Não dá pra desfazer.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle().strokeBorder(Color.black, lineWidth: 2.5)
                Image(systemName: "pencil.and.outline")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 0) {
                Text("Meus Cadernos")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                if !notebooks.isEmpty {
                    Text("\(notebooks.count) \(notebooks.count == 1 ? "caderno" : "cadernos")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var addButton: some View {
        Button(action: addNotebook) {
            ZStack {
                Circle().fill(Color.black).offset(x: 3, y: 3)
                Circle().fill(Color.accentColor.gradient)
                Circle().strokeBorder(Color.black, lineWidth: 2.5)
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 60, height: 60)
        }
        .accessibilityLabel("Novo caderno")
    }

    private func notebookCell(for notebook: Notebook) -> some View {
        NavigationLink(value: notebook.id) {
            ZStack(alignment: .bottomTrailing) {
                NotebookCoverView(notebook: notebook)
                Menu {
                    Button {
                        renamingNotebook = notebook
                    } label: {
                        Label("Renomear", systemImage: "pencil")
                    }
                    Button {
                        editingColorNotebook = notebook
                    } label: {
                        Label("Cor da capa", systemImage: "paintpalette")
                    }
                    Button(role: .destructive) {
                        deletingNotebook = notebook
                    } label: {
                        Label("Excluir caderno", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, .black.opacity(0.35))
                        .padding(6)
                }
                .padding([.bottom, .trailing], 20)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renamingNotebook = notebook
            } label: {
                Label("Renomear", systemImage: "pencil")
            }
            Button {
                editingColorNotebook = notebook
            } label: {
                Label("Cor da capa", systemImage: "paintpalette")
            }
            Button(role: .destructive) {
                deletingNotebook = notebook
            } label: {
                Label("Excluir caderno", systemImage: "trash")
            }
        }
    }

    private func addNotebook() {
        let notebook = Notebook(
            title: "Caderno \(notebooks.count + 1)",
            coverColor: NotebookColor.forOrder(notebooks.count)
        )
        let section = Section(title: "Geral", order: 0)
        section.notebook = notebook
        notebook.sections.append(section)
        let page = NotebookPage(order: 0)
        page.section = section
        section.pages.append(page)
        modelContext.insert(notebook)
    }

    private func delete(_ notebook: Notebook) {
        for section in notebook.sections {
            for page in section.pages {
                DrawingStore.delete(fileName: page.drawingFileName)
            }
        }
        modelContext.delete(notebook)
    }
}

#Preview {
    NotebookListView()
        .modelContainer(for: [Notebook.self, Section.self, NotebookPage.self], inMemory: true)
}
