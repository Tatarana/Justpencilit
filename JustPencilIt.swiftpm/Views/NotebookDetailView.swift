import SwiftUI
import SwiftData
import UIKit

/// Tela de um caderno aberto: abas de seção no topo, carrossel de páginas
/// da seção selecionada embaixo, e um painel lateral opcional (desliza da
/// direita) com os áudios/transcrições etiquetados à seção aberta.
struct NotebookDetailView: View {
    @Bindable var notebook: Notebook
    // Preenchidos quando se chega aqui vindo de um resultado de busca —
    // fazem a tela já abrir direto na seção/página certa, em vez de sempre
    // cair na primeira seção.
    var initialSectionID: UUID? = nil
    var initialPageIndex: Int? = nil
    // Chamado quando a busca daqui de dentro aponta pra algo que não é
    // desta mesma seção/deste mesmo caderno (outro caderno, uma coleção, um
    // áudio) — quem constrói esta tela (NotebookListView) decide como
    // navegar até lá, já que só ela tem o NavigationPath da tela inicial.
    var onJumpElsewhere: (SearchResult.Target) -> Void = { _ in }
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioMemo.createdAt) private var allAudioMemos: [AudioMemo]

    @State private var selectedSectionID: UUID?
    @State private var selectedPageIndex = 0
    @State private var isRenamingNotebook = false
    @State private var renamingSection: Section?
    @State private var editingBackgroundSection: Section?
    @State private var isEditingCoverColor = false
    @State private var isEditingNotebookPaper = false
    @State private var penKind: PenKind = .pen
    @State private var penColor: PenColor = .black
    @State private var isShowingAudioPanel = false
    @State private var isShowingPageGrid = false
    @State private var isShowingSearch = false
    // Preenchido depois que um PDF termina de ser gerado (ver
    // `protectedExportAction`) — dispara o `.sheet` de compartilhamento
    // nativo (AirDrop, Mail, Salvar em Arquivos etc).
    @State private var exportedPDFURL: URL?
    @State private var isShowingShareSheet = false

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
                    onDelete: deleteSection,
                    onDropPages: { target, ids in
                        movePages(idStrings: ids, to: target)
                    }
                )
                Divider()
                if let section = selectedSection {
                    if isShowingPageGrid {
                        PageGridView(
                            section: section,
                            otherSections: notebook.sortedSections.filter { $0.id != section.id },
                            onOpenPage: { index in
                                selectedPageIndex = index
                                isShowingPageGrid = false
                            },
                            onMovePages: { ids, target in
                                movePages(ids: ids, to: target)
                            },
                            onExportPages: { ids in
                                exportPages(ids)
                            },
                            onDeletePages: { ids in
                                deletePages(ids)
                            },
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isShowingPageGrid = false
                                }
                            }
                        )
                    } else {
                        PageCarouselView(
                            section: section,
                            selectedPageIndex: $selectedPageIndex,
                            isActive: !isEditingAnything,
                            penKind: $penKind,
                            penColor: $penColor,
                            onShowGrid: { isShowingPageGrid = true }
                        )
                    }
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
        // Sem o gesto de "voltar" deslizando: arrastar pra virar pra página
        // anterior acabava saindo do caderno. Pra sair, só o botão de voltar.
        .background(BackSwipeBlocker())
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(notebook.title)
                    .font(.custom(NotebookCoverView.titleFontName, size: 22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Buscar")
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
                    Button {
                        isEditingNotebookPaper = true
                    } label: {
                        Label("Papel padrão do caderno", systemImage: "doc.plaintext")
                    }
                    if let section = selectedSection {
                        Button {
                            editingBackgroundSection = section
                        } label: {
                            Label("Fundo da seção", systemImage: "square.grid.3x3")
                        }
                        Button {
                            exportSection(section)
                        } label: {
                            Label("Exportar seção (PDF)", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            deleteCurrentPage()
                        } label: {
                            Label("Excluir página atual", systemImage: "trash")
                        }
                    }
                    Button {
                        exportNotebook()
                    } label: {
                        Label("Exportar caderno inteiro (PDF)", systemImage: "doc.zipper")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear(perform: ensureAtLeastOneSection)
        .confirmationDialog(
            "Papel padrão do caderno",
            isPresented: $isEditingNotebookPaper,
            titleVisibility: .visible
        ) {
            Button("Igual ao padrão geral (\(PageBackground.appDefault.label))") {
                notebook.defaultBackground = nil
            }
            ForEach(PageBackground.allCases) { style in
                Button(style.label) {
                    notebook.defaultBackground = style
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Vale pras seções novas deste caderno. As que já existem não mudam (pra trocar uma delas, use \"Fundo da seção\").")
        }
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
        .fullScreenCover(isPresented: $isShowingSearch) {
            SearchView(
                onSelectCollection: { collection in handleSearchSelection(.collection(collection)) },
                onSelectNotebook: { targetNotebook in handleSearchSelection(.notebook(targetNotebook)) },
                onSelectSection: { section in handleSearchSelection(.section(section)) },
                onSelectPage: { page in handleSearchSelection(.page(page)) },
                onSelectAudioMemo: { memo in handleSearchSelection(.audioMemo(memo)) }
            )
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let exportedPDFURL {
                ShareSheet(items: [exportedPDFURL])
            }
        }
    }

    /// Resultado de busca tocado dentro do próprio caderno: se aponta pra
    /// algo desta mesma seção/deste mesmo caderno, só ajusta a seleção
    /// local (sem sair daqui); senão, delega pra quem construiu esta tela
    /// decidir como chegar lá (`onJumpElsewhere`).
    private func handleSearchSelection(_ target: SearchResult.Target) {
        isShowingSearch = false
        switch target {
        case .collection:
            onJumpElsewhere(target)
        case .notebook(let targetNotebook):
            guard targetNotebook.id != notebook.id else { return }
            onJumpElsewhere(target)
        case .section(let section):
            if section.notebook?.id == notebook.id {
                selectedSectionID = section.id
                isShowingPageGrid = false
            } else {
                onJumpElsewhere(target)
            }
        case .page(let page):
            if let section = page.section, section.notebook?.id == notebook.id {
                selectedSectionID = section.id
                selectedPageIndex = section.sortedPages.firstIndex(where: { $0.id == page.id }) ?? 0
                isShowingPageGrid = false
            } else {
                onJumpElsewhere(target)
            }
        case .audioMemo:
            onJumpElsewhere(target)
        }
    }

    private func ensureAtLeastOneSection() {
        if notebook.sections.isEmpty {
            let section = Section(title: "Geral", order: 0, backgroundStyle: notebook.effectiveDefaultBackground)
            section.notebook = notebook
            notebook.sections.append(section)
            let page = NotebookPage(order: 0)
            page.section = section
            section.pages.append(page)
        }
        if selectedSectionID == nil {
            if let initialSectionID, notebook.sortedSections.contains(where: { $0.id == initialSectionID }) {
                selectedSectionID = initialSectionID
                if let initialPageIndex {
                    selectedPageIndex = initialPageIndex
                }
            } else if let bookmark = bookmarkedLocation() {
                // Abre direto na página marcada.
                selectedSectionID = bookmark.sectionID
                selectedPageIndex = bookmark.pageIndex
            } else {
                selectedSectionID = notebook.sortedSections.first?.id
                if let initialPageIndex {
                    selectedPageIndex = initialPageIndex
                }
            }
        }
    }

    /// Seção e posição da página marcada, se o marcador ainda existir.
    private func bookmarkedLocation() -> (sectionID: UUID, pageIndex: Int)? {
        guard let pageID = notebook.bookmarkedPageID else { return nil }
        for section in notebook.sortedSections {
            if let index = section.sortedPages.firstIndex(where: { $0.id == pageID }) {
                return (section.id, index)
            }
        }
        return nil
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

    /// Move as páginas com esses ids (de qualquer seção deste caderno) pra
    /// `target`, colocando-as no final — usado tanto pelo "Mover para" da
    /// grade (várias de uma vez) quanto por soltar numa aba (uma ou várias,
    /// se já estavam selecionadas).
    private func movePages(ids: Set<UUID>, to target: Section) {
        let allPages = notebook.sortedSections.flatMap { $0.sortedPages }
        let toMove = allPages.filter { ids.contains($0.id) && $0.section?.id != target.id }
        guard !toMove.isEmpty else { return }
        var nextOrder = target.pages.count
        for page in toMove {
            page.section = target
            page.order = nextOrder
            nextOrder += 1
        }
    }

    /// Mesma coisa, recebendo os ids como strings (vem do drag-and-drop,
    /// que trafega `PageDragPayload.pageIDs: [String]`).
    private func movePages(idStrings: [String], to target: Section) {
        let ids = Set(idStrings.compactMap { UUID(uuidString: $0) })
        movePages(ids: ids, to: target)
    }

    /// Apaga de vez as páginas selecionadas na grade — arquivo `.drawing`
    /// em disco e registro no banco. A grade já confirma com a pessoa e já
    /// trava o botão antes de chamar isto se a seleção fosse apagar TODAS
    /// as páginas da seção; a segunda checagem aqui é só uma rede de
    /// segurança extra, mesma regra do apagar a página atual no carrossel
    /// (`deleteCurrentPage`) — uma seção nunca pode ficar com zero páginas.
    private func deletePages(_ ids: Set<UUID>) {
        guard let section = selectedSection else { return }
        let pages = section.sortedPages
        let toDelete = pages.filter { ids.contains($0.id) }
        guard !toDelete.isEmpty, toDelete.count < pages.count else { return }
        for page in toDelete {
            DrawingStore.delete(fileName: page.drawingFileName)
            modelContext.delete(page)
        }
        let remaining = max(section.sortedPages.count - 1, 0)
        selectedPageIndex = min(selectedPageIndex, remaining)
    }

    // MARK: - Exportar em PDF

    private func exportSection(_ section: Section) {
        protectedExportAction {
            guard let url = PDFExportService.export(section: section) else { return }
            presentShareSheet(for: url)
        }
    }

    private func exportNotebook() {
        protectedExportAction {
            guard let url = PDFExportService.export(notebook: notebook) else { return }
            presentShareSheet(for: url)
        }
    }

    /// Exportação de uma seleção feita na grade de miniaturas — as páginas
    /// podem vir de qualquer seção deste caderno, então procura entre todas.
    private func exportPages(_ ids: Set<UUID>) {
        protectedExportAction {
            let allPages = notebook.sortedSections.flatMap { $0.sortedPages }
            let selected = allPages.filter { ids.contains($0.id) }
            guard let url = PDFExportService.export(pages: selected, suggestedName: notebook.title) else { return }
            presentShareSheet(for: url)
        }
    }

    private func presentShareSheet(for url: URL) {
        exportedPDFURL = url
        isShowingShareSheet = true
    }

    /// Exportar é o próprio ato de tirar conteúdo do app (AirDrop, e-mail,
    /// Arquivos) — por isso SEMPRE pede Face ID/senha de novo quando o
    /// caderno (ou a coleção dele) está protegido, mesmo que a pessoa já
    /// tenha desbloqueado uma vez só pra abrir o caderno nesta visita. As
    /// outras ações daqui de dentro (renomear, excluir página) não pedem de
    /// novo porque não fazem o conteúdo sair do app.
    private func protectedExportAction(_ action: @escaping () -> Void) {
        let isProtected = notebook.isLocked || (notebook.group?.isLocked ?? false)
        guard isProtected else {
            action()
            return
        }
        Task {
            let success = await BiometricLock.authenticate(reason: "Exportar conteúdo de \"\(notebook.title)\"")
            if success { action() }
        }
    }
}


/// Desliga o gesto de deslizar pra voltar (da borda e, no iOS 26, de
/// qualquer ponto da tela) enquanto o caderno está aberto, e religa ao sair.
private struct BackSwipeBlocker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setBackSwipe(enabled: false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setBackSwipe(enabled: true)
        }

        private func setBackSwipe(enabled: Bool) {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = enabled
            navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = enabled
        }
    }
}
