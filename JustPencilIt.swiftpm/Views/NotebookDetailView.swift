import SwiftUI

/// Tela de um caderno aberto: abas de seção no topo, carrossel de páginas
/// da seção selecionada embaixo.
struct NotebookDetailView: View {
    @Bindable var notebook: Notebook
    @Environment(\.modelContext) private var modelContext

    @State private var selectedSectionID: UUID?
    @State private var selectedPageIndex = 0
    @State private var isRenamingNotebook = false
    @State private var renamingSection: Section?
    @State private var editingBackgroundSection: Section?
    @State private var isEditingCoverColor = false
    @State private var penKind: PenKind = .pen
    @State private var penColor: PenColor = .black

    private var selectedSection: Section? {
        notebook.sortedSections.first { $0.id == selectedSectionID }
    }

    private var isEditingAnything: Bool {
        isRenamingNotebook || renamingSection != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionTabsView(
                notebook: notebook,
                selectedSectionID: $selectedSectionID,
                onRename: { renamingSection = $0 },
                onDelete: deleteSection
            )
            Divider()
            if let section = selectedSection {
                PageCarouselView(
                    section: section,
                    selectedPageIndex: $selectedPageIndex,
                    isActive: !isEditingAnything,
                    penKind: $penKind,
                    penColor: $penColor
                )
            } else {
                ContentUnavailableView(
                    "Sem seções",
                    systemImage: "tray",
                    description: Text("Toque em + para criar a primeira seção.")
                )
            }
        }
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isRenamingNotebook = true
                    } label: {
                        Label("Renomear caderno", systemImage: "pencil")
                    }
                    Button {
                        isEditingCoverColor = true
                    } label: {
                        Label("Cor da capa", systemImage: "paintpalette")
                    }
                    if let section = selectedSection {
                        Button {
                            editingBackgroundSection = section
                        } label: {
                            Label("Fundo da seção", systemImage: "square.grid.3x3")
                        }
                        Button(role: .destructive) {
                            deleteCurrentPage()
                        } label: {
                            Label("Excluir página atual", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear(perform: ensureAtLeastOneSection)
        .sheet(isPresented: $isRenamingNotebook) {
            RenameSheet(originalTitle: notebook.title) { newTitle in
                notebook.title = newTitle
                notebook.updatedAt = Date()
            }
        }
        .sheet(item: $renamingSection) { section in
            RenameSheet(originalTitle: section.title) { newTitle in
                section.title = newTitle
            }
        }
        .confirmationDialog(
            "Fundo da seção",
            isPresented: Binding(
                get: { editingBackgroundSection != nil },
                set: { isPresented in
                    if !isPresented { editingBackgroundSection = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            ForEach(PageBackground.allCases) { style in
                Button(style.label) {
                    editingBackgroundSection?.backgroundStyle = style
                    editingBackgroundSection = nil
                }
            }
        }
        .confirmationDialog(
            "Cor da capa",
            isPresented: $isEditingCoverColor,
            titleVisibility: .visible
        ) {
            ForEach(NotebookColor.allCases) { option in
                Button(option.label) {
                    notebook.coverColor = option
                }
            }
        }
    }

    private func ensureAtLeastOneSection() {
        if notebook.sections.isEmpty {
            let section = Section(title: "Geral", order: 0)
            section.notebook = notebook
            notebook.sections.append(section)
            let page = NotebookPage(order: 0)
            page.section = section
            section.pages.append(page)
        }
        if selectedSectionID == nil {
            selectedSectionID = notebook.sortedSections.first?.id
        }
    }

    private func deleteSection(_ section: Section) {
        for page in section.pages {
            DrawingStore.delete(fileName: page.drawingFileName)
        }
        modelContext.delete(section)
        if selectedSectionID == section.id {
            selectedSectionID = notebook.sortedSections.first(where: { $0.id != section.id })?.id
            selectedPageIndex = 0
        }
    }

    private func deleteCurrentPage() {
        guard let section = selectedSection else { return }
        let pages = section.sortedPages
        guard pages.count > 1, pages.indices.contains(selectedPageIndex) else { return }
        let page = pages[selectedPageIndex]
        DrawingStore.delete(fileName: page.drawingFileName)
        modelContext.delete(page)
        selectedPageIndex = max(0, selectedPageIndex - 1)
    }
}
