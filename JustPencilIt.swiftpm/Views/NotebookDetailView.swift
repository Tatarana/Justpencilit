import SwiftUI
import SwiftData

/// Tela de um caderno aberto: abas de seção no topo, carrossel de páginas
/// da seção selecionada embaixo, e um painel lateral opcional (desliza da
/// direita) com os áudios/transcrições etiquetados à seção aberta.
struct NotebookDetailView: View {
    @Bindable var notebook: Notebook
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioMemo.createdAt) private var allAudioMemos: [AudioMemo]

    @State private var selectedSectionID: UUID?
    @State private var selectedPageIndex = 0
    @State private var isRenamingNotebook = false
    @State private var renamingSection: Section?
    @State private var editingBackgroundSection: Section?
    @State private var isEditingCoverColor = false
    @State private var penKind: PenKind = .pen
    @State private var penColor: PenColor = .black
    @State private var isShowingAudioPanel = false

    private var selectedSection: Section? {
        notebook.sortedSections.first { $0.id == selectedSectionID }
    }

    private var isEditingAnything: Bool {
        isRenamingNotebook || renamingSection != nil
    }

    /// Quantos memos a seção aberta agora já tem — vira uma bolinha no
    /// botão do painel, pra avisar que tem algo lá sem precisar abrir.
    private var sectionAudioCount: Int {
        guard let selectedSectionID else { return 0 }
        return allAudioMemos.filter { $0.section?.id == selectedSectionID }.count
    }

    var body: some View {
        // ZStack (não HStack) de propósito: o painel flutua POR CIMA do
        // carrossel, em vez de empurrá-lo — com HStack não havia nada
        // "atrás" do painel pro material translúcido borrar, então o vidro
        // fosco não tinha efeito nenhum na prática. Flutuando por cima, dá
        // pra ver a página desfocada por trás do painel de verdade.
        ZStack(alignment: .trailing) {
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

            if isShowingAudioPanel {
                AudioSectionPanelView(section: selectedSection) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isShowingAudioPanel = false
                    }
                }
                .frame(width: 320)
                .frame(maxHeight: .infinity)
                .shadow(color: .black.opacity(0.18), radius: 16, x: -4, y: 0)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        // O título nativo (.navigationTitle) não deixa trocar a fonte, então
        // usamos um item de toolbar central com o mesmo texto, na mesma
        // fonte cursiva do nome na capa — assim o nome do caderno "segue"
        // pra tela aberta.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(notebook.title)
                    .font(.custom(NotebookCoverView.titleFontName, size: 22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isShowingAudioPanel.toggle()
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "recordingtape")
                        if sectionAudioCount > 0 {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                                .offset(x: 5, y: -3)
                        }
                    }
                }
                .accessibilityLabel("Áudios da seção")
            }
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
