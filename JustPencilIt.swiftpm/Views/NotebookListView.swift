import SwiftUI
import SwiftData

/// Tela inicial: os cadernos do usuário organizados em "estantes" (coleções,
/// ex: Trabalho, Pessoal, RPG) que expandem/recolhem, cada uma com sua
/// grade de capas estilo gibi/mangá. Cadernos sem coleção caem numa estante
/// "Outros". Sem nenhuma coleção criada, a tela mostra a grade simples.
/// Dá pra arrastar um caderno de uma estante pra outra pra movê-lo.
struct NotebookListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Notebook.updatedAt, order: .reverse) private var notebooks: [Notebook]
    @Query(sort: \NotebookGroup.order) private var collections: [NotebookGroup]

    @State private var renamingNotebook: Notebook?
    @State private var editingColorNotebook: Notebook?
    @State private var deletingNotebook: Notebook?

    @State private var renamingCollection: NotebookGroup?
    @State private var editingColorCollection: NotebookGroup?
    @State private var deletingCollection: NotebookGroup?
    @State private var collapsedShelfIDs: Set<UUID> = []
    @State private var createTrigger = 0
    @State private var deleteTrigger = 0
    @State private var collectionTrigger = 0
    @State private var recordTrigger = 0
    @State private var scrollFraction: CGFloat = 0
    @State private var isShowingLibrary = false
    @State private var isShowingSearch = false
    @State private var isShowingSettings = false
    // Preenchidos por um resultado de busca antes de navegar, pra abrir a
    // seção/página certa (cadernos) ou o memo certo (áudios) — sempre
    // reiniciados quando a navegação começa de outro lugar (toque normal
    // numa capa, ou no rádio-gravador).
    @State private var pendingSectionID: UUID?
    @State private var pendingPageIndex: Int?
    @State private var pendingAudioMemoID: UUID?
    // Navegação por código (em vez de só NavigationLink) — precisamos disso
    // pra poder pedir Face ID/senha ANTES de empurrar a tela do caderno,
    // quando ele (ou a coleção dele) está protegido.
    @State private var path = NavigationPath()
    @State private var didInitializeCollapsedShelves = false

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 4)]

    /// UUID fixo só pra identificar a estante "Favoritos" no estado de
    /// colapsar/expandir — mesma ideia do `NotebookGroup.ungroupedShelfID`
    /// lá embaixo, nunca é salvo em disco.
    private static let favoritesShelfID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private var ungroupedNotebooks: [Notebook] {
        notebooks.filter { $0.group == nil }
    }

    /// Cadernos favoritados, mais recente primeiro — igual a `notebooks`,
    /// que já vem ordenada assim pela @Query.
    private var favoriteNotebooks: [Notebook] {
        notebooks.filter { $0.isFavorite }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                MascotBackgroundView(
                    notebookCount: notebooks.count,
                    scrollFraction: scrollFraction,
                    createTrigger: createTrigger,
                    deleteTrigger: deleteTrigger,
                    collectionTrigger: collectionTrigger,
                    recordTrigger: recordTrigger
                )
                .ignoresSafeArea()

                ScrollView {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: proxy.frame(in: .named("notebookScroll")).minY
                        )
                    }
                    .frame(height: 0)

                    header

                    if !favoriteNotebooks.isEmpty {
                        favoritesShelf
                    }

                    if notebooks.isEmpty {
                        ContentUnavailableView(
                            "Nenhum caderno ainda",
                            systemImage: "pencil.and.outline",
                            description: Text("Toque no + para criar seu primeiro caderno.")
                        )
                        .padding(.top, 60)
                    } else if collections.isEmpty {
                        // Sem coleções criadas ainda: grade simples, sem cabeçalhos.
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(notebooks) { notebook in
                                notebookCell(for: notebook)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 90)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(collections) { collection in
                                shelf(
                                    collection: collection,
                                    notebooks: collection.notebooks.sorted { $0.updatedAt > $1.updatedAt }
                                )
                            }
                            shelf(collection: nil, notebooks: ungroupedNotebooks)
                        }
                        .padding(.bottom, 90)
                    }
                }
                .coordinateSpace(name: "notebookScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { minY in
                    let normalized = max(-1, min(1, -minY / 700))
                    withAnimation(.easeOut(duration: 0.25)) { scrollFraction = normalized }
                }

                // Rádio-gravador ao lado do "+" (antes ficava fixo no canto
                // superior direito e cobria o botão de nova coleção).
                HStack(alignment: .bottom, spacing: 20) {
                    RadioRecorderButton {
                        // A gravação em si só abre de dentro da fitoteca
                        // (como uma janela por cima dela) — o rádio-gravador
                        // daqui leva pra lá primeiro.
                        recordTrigger += 1
                        pendingAudioMemoID = nil
                        isShowingLibrary = true
                    }
                    addButton
                }
                .padding(24)

                // Lupa no canto inferior esquerdo — faz par com o "+" de
                // novo caderno (inferior direito), longe do cabeçalho lá
                // em cima (que rola junto com o conteúdo — um botão fixo
                // ali em cima colidia com o ícone "Meus Cadernos").
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        searchButton
                        settingsButton
                        Spacer()
                    }
                }
                .padding(24)
            }
            // O fundo (mascote) é sempre claro — então a tela de cadernos
            // fica sempre em modo claro, senão no modo escuro do iPad os
            // títulos ("Meus Cadernos", nomes das coleções) ficavam brancos
            // e ilegíveis.
            .environment(\.colorScheme, .light)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { notebookID in
                if let notebook = notebooks.first(where: { $0.id == notebookID }) {
                    NotebookDetailView(
                        notebook: notebook,
                        initialSectionID: pendingSectionID,
                        initialPageIndex: pendingPageIndex,
                        onJumpElsewhere: { target in
                            jumpElsewhere(target)
                        }
                    )
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(item: $renamingNotebook) { notebook in
                RenameSheet(originalTitle: notebook.title) { newTitle in
                    notebook.title = newTitle
                    notebook.updatedAt = Date()
                }
            }
            .sheet(item: $renamingCollection) { collection in
                RenameSheet(originalTitle: collection.title) { newTitle in
                    collection.title = newTitle
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
            .confirmationDialog(
                "Cor da coleção",
                isPresented: Binding(
                    get: { editingColorCollection != nil },
                    set: { isPresented in
                        if !isPresented { editingColorCollection = nil }
                    }
                ),
                titleVisibility: .visible
            ) {
                ForEach(NotebookColor.allCases) { option in
                    Button(option.label) {
                        editingColorCollection?.color = option
                        editingColorCollection = nil
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
            .alert(
                "Excluir coleção \"\(deletingCollection?.title ?? "")\"?",
                isPresented: Binding(
                    get: { deletingCollection != nil },
                    set: { isPresented in
                        if !isPresented { deletingCollection = nil }
                    }
                )
            ) {
                Button("Cancelar", role: .cancel) { deletingCollection = nil }
                Button("Excluir coleção", role: .destructive) {
                    if let collection = deletingCollection {
                        modelContext.delete(collection)
                    }
                    deletingCollection = nil
                }
            } message: {
                Text("Os cadernos dessa coleção não são apagados — eles só ficam sem coleção.")
            }
            .fullScreenCover(isPresented: $isShowingLibrary) {
                AudioLibraryView(
                    initialMemoID: pendingAudioMemoID,
                    onJumpElsewhere: { target in
                        isShowingLibrary = false
                        jumpElsewhere(target)
                    }
                )
            }
            .fullScreenCover(isPresented: $isShowingSearch) {
                SearchView(
                    onSelectCollection: { _ in
                        // Só fecha a busca — a coleção já fica visível
                        // (com título e cadeado, se protegida) na tela
                        // inicial, não precisa de mais navegação.
                        isShowingSearch = false
                    },
                    onSelectNotebook: { notebook in
                        isShowingSearch = false
                        openNotebook(notebook)
                    },
                    onSelectSection: { section in
                        isShowingSearch = false
                        guard let notebook = section.notebook else { return }
                        openNotebook(notebook, sectionID: section.id)
                    },
                    onSelectPage: { page in
                        isShowingSearch = false
                        guard let section = page.section, let notebook = section.notebook else { return }
                        let index = section.sortedPages.firstIndex(where: { $0.id == page.id }) ?? 0
                        openNotebook(notebook, sectionID: section.id, pageIndex: index)
                    },
                    onSelectAudioMemo: { memo in
                        isShowingSearch = false
                        pendingAudioMemoID = memo.id
                        isShowingLibrary = true
                    }
                )
            }
            .onAppear {
                // Ao abrir o app, coleções protegidas começam recolhidas —
                // senão os cadernos dela apareceriam na grade antes mesmo
                // de pedir Face ID/senha. Só roda uma vez por visita a essa
                // tela, pra não recolher de novo algo que o usuário abriu.
                guard !didInitializeCollapsedShelves else { return }
                didInitializeCollapsedShelves = true
                collapsedShelfIDs.formUnion(collections.filter { $0.isLocked }.map { $0.id })
            }
            .task {
                // Varredura de páginas com OCR pendente — pega qualquer
                // coisa que ficou pra trás (app fechado no meio, etc).
                await OCRService.catchUpSweep(modelContext: modelContext)
            }
            .task(priority: .utility) {
                // Garante que o arquivo do banco esteja protegido — os
                // desenhos e áudios já nascem protegidos na escrita, não
                // precisam de nenhum passo extra aqui.
                FileProtection.protectDatabase(modelContext: modelContext)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await OCRService.catchUpSweep(modelContext: modelContext) }
            }
        }
    }

    private var searchButton: some View {
        Button {
            isShowingSearch = true
        } label: {
            ZStack {
                Circle().fill(Color.black).offset(x: 2, y: 2)
                Circle().fill(
                    LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                Circle().strokeBorder(Color.black, lineWidth: 2.5)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 50, height: 50)
        }
        .accessibilityLabel("Buscar")
    }

    private var settingsButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            ZStack {
                Circle().fill(Color.black).offset(x: 2, y: 2)
                Circle().fill(Color(.secondarySystemBackground))
                Circle().strokeBorder(Color.black, lineWidth: 2.5)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Ajustes")
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

            // Mesmo estilo mangá dos outros botões (contorno preto grosso,
            // sombra dura): pilha de cadernos com um "+" amarelo de adesivo.
            Button(action: addCollection) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle().fill(Color.black).offset(x: 2, y: 2)
                        Circle().fill(
                            LinearGradient(
                                colors: [Color.green, Color.teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        Circle().strokeBorder(Color.black, lineWidth: 2.5)
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 44, height: 44)

                    ZStack {
                        Circle().fill(Color.yellow)
                        Circle().strokeBorder(Color.black, lineWidth: 2)
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.black)
                    }
                    .frame(width: 20, height: 20)
                    .offset(x: 5, y: -5)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nova coleção")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// Estante fixa no topo com os cadernos favoritados — mesma mecânica de
    /// colapsar/expandir das outras estantes, mas sem menu de gerenciar e
    /// sem aceitar arrastar-e-soltar (favoritar é só pelo menu do caderno).
    private var favoritesShelf: some View {
        let isExpanded = !collapsedShelfIDs.contains(Self.favoritesShelfID)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        collapsedShelfIDs.insert(Self.favoritesShelfID)
                    } else {
                        collapsedShelfIDs.remove(Self.favoritesShelfID)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(Color.yellow)
                    Text("Favoritos")
                        .font(.custom("BradleyHandITCTT-Bold", size: 22))
                        .foregroundStyle(.primary)
                    Text("\(favoriteNotebooks.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            if isExpanded {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(favoriteNotebooks) { notebook in
                        notebookCell(for: notebook)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    /// Uma estante colapsável. `collection == nil` representa a estante
    /// especial "Outros" (cadernos sem coleção) — sem menu de gerenciar.
    /// Aceita cadernos soltos aqui via arrastar-e-soltar (`.dropDestination`);
    /// cada capa oferece o mesmo id como payload via `.draggable`.
    @ViewBuilder
    private func shelf(collection: NotebookGroup?, notebooks: [Notebook]) -> some View {
        let shelfID = collection?.id ?? NotebookGroup.ungroupedShelfID
        let isExpanded = !collapsedShelfIDs.contains(shelfID)
        let title = collection?.title ?? "Outros"
        let color = collection?.color.color ?? Color(.systemGray)

        let isLocked = collection?.isLocked ?? false

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    toggleShelf(shelfID: shelfID, isExpanded: isExpanded, isLocked: isLocked, title: title)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Circle().fill(color).frame(width: 10, height: 10)
                        Text(title)
                            .font(.custom("BradleyHandITCTT-Bold", size: 22))
                            .foregroundStyle(.primary)
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        Text("\(notebooks.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if let collection {
                    collectionMenu(for: collection)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            if isExpanded {
                if notebooks.isEmpty {
                    Text("Arraste um caderno até aqui, ou nenhum caderno ainda.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(notebooks) { notebook in
                            notebookCell(for: notebook)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color.clear)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first,
                  let uuid = UUID(uuidString: idString),
                  let notebook = notebooks.first(where: { $0.id == uuid }) ?? self.notebooks.first(where: { $0.id == uuid })
            else { return false }
            // Arrastar também é uma forma de "mover" — passa pela mesma
            // trava que o menu, senão daria pra contornar a proteção só
            // arrastando o caderno pra outra estante.
            protectedNotebookAction(notebook, reason: "Mover \"\(notebook.title)\"") {
                notebook.group = collection
            }
            return true
        }
    }

    private func collectionMenu(for collection: NotebookGroup) -> some View {
        Menu {
            Button {
                protectedCollectionAction(collection, reason: "Renomear \"\(collection.title)\"") {
                    renamingCollection = collection
                }
            } label: {
                Label("Renomear coleção", systemImage: "pencil")
            }
            Button {
                protectedCollectionAction(collection, reason: "Mudar a cor de \"\(collection.title)\"") {
                    editingColorCollection = collection
                }
            } label: {
                Label("Cor da coleção", systemImage: "paintpalette")
            }
            Button {
                toggleCollectionLock(collection)
            } label: {
                if collection.isLocked {
                    Label("Remover proteção", systemImage: "lock.open")
                } else {
                    Label("Proteger coleção", systemImage: "lock")
                }
            }
            Button(role: .destructive) {
                protectedCollectionAction(collection, reason: "Excluir \"\(collection.title)\"") {
                    deletingCollection = collection
                }
            } label: {
                Label("Excluir coleção", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(6)
        }
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
        Button {
            openNotebook(notebook)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                NotebookCoverView(notebook: notebook)
                Menu {
                    notebookMenuContent(for: notebook)
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
        .draggable(notebook.id.uuidString) {
            // Prévia leve durante o arrasto, em vez da capa inteira (evita
            // recriar a sombra dura duplicada, que fica estranha arrastando).
            Text(notebook.title)
                .font(.system(.body, design: .rounded).weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(notebook.coverColor.color, in: Capsule())
                .foregroundStyle(.white)
        }
        .contextMenu {
            notebookMenuContent(for: notebook)
        }
    }

    /// Conteúdo do menu de um caderno — usado tanto no menu (•••) quanto no
    /// toque longo (contextMenu). Todo mundo aqui (menos o próprio toggle de
    /// proteção) passa por `protectedNotebookAction`: se o caderno estiver
    /// protegido, pede Face ID/senha antes de renomear, mudar cor, mover de
    /// coleção ou excluir — não só antes de abrir.
    @ViewBuilder
    private func notebookMenuContent(for notebook: Notebook) -> some View {
        Button {
            protectedNotebookAction(notebook, reason: "Renomear \"\(notebook.title)\"") {
                renamingNotebook = notebook
            }
        } label: {
            Label("Renomear", systemImage: "pencil")
        }
        Button {
            protectedNotebookAction(notebook, reason: "Mudar a cor de \"\(notebook.title)\"") {
                editingColorNotebook = notebook
            }
        } label: {
            Label("Cor da capa", systemImage: "paintpalette")
        }
        Button {
            notebook.isFavorite.toggle()
        } label: {
            if notebook.isFavorite {
                Label("Remover dos favoritos", systemImage: "star.slash")
            } else {
                Label("Favoritar", systemImage: "star")
            }
        }
        Button {
            toggleNotebookLock(notebook)
        } label: {
            if notebook.isLocked {
                Label("Remover proteção", systemImage: "lock.open")
            } else {
                Label("Proteger caderno", systemImage: "lock")
            }
        }
        Menu {
            Button {
                protectedNotebookAction(notebook, reason: "Mover \"\(notebook.title)\"") {
                    notebook.group = nil
                }
            } label: {
                if notebook.group == nil {
                    Label("Sem coleção", systemImage: "checkmark")
                } else {
                    Text("Sem coleção")
                }
            }
            ForEach(collections) { collection in
                Button {
                    protectedNotebookAction(notebook, reason: "Mover \"\(notebook.title)\"") {
                        notebook.group = collection
                    }
                } label: {
                    if notebook.group?.id == collection.id {
                        Label(collection.title, systemImage: "checkmark")
                    } else {
                        Text(collection.title)
                    }
                }
            }
        } label: {
            Label("Mover para coleção", systemImage: "folder")
        }
        Button(role: .destructive) {
            protectedNotebookAction(notebook, reason: "Excluir \"\(notebook.title)\"") {
                deletingNotebook = notebook
            }
        } label: {
            Label("Excluir caderno", systemImage: "trash")
        }
    }

    private func addNotebook() {
        let notebook = Notebook(
            title: "Caderno \(notebooks.count + 1)",
            coverColor: NotebookColor.forOrder(notebooks.count)
        )
        let section = Section(title: "Geral", order: 0, backgroundStyle: notebook.effectiveDefaultBackground)
        section.notebook = notebook
        notebook.sections.append(section)
        let page = NotebookPage(order: 0)
        page.section = section
        section.pages.append(page)
        modelContext.insert(notebook)
        createTrigger += 1
    }

    private func addCollection() {
        let collection = NotebookGroup(
            title: "Coleção \(collections.count + 1)",
            order: collections.count,
            color: NotebookColor.forOrder(collections.count + 1)
        )
        modelContext.insert(collection)
        collectionTrigger += 1
    }

    private func delete(_ notebook: Notebook) {
        for section in notebook.sections {
            for page in section.pages {
                DrawingStore.delete(fileName: page.drawingFileName)
            }
        }
        modelContext.delete(notebook)
        deleteTrigger += 1
    }

    // MARK: - Proteção (Face ID/Touch ID/senha do iPad)

    /// Roda `action` na hora se o caderno (ou a coleção dele) não estiver
    /// protegido; senão pede Face ID/senha primeiro. Usado por TODAS as
    /// ações que mexem num caderno protegido — abrir, renomear, mudar cor,
    /// mover de coleção, excluir — não só abrir.
    private func protectedNotebookAction(_ notebook: Notebook, reason: String, action: @escaping () -> Void) {
        let isProtected = notebook.isLocked || (notebook.group?.isLocked ?? false)
        guard isProtected else {
            action()
            return
        }
        Task {
            let success = await BiometricLock.authenticate(reason: reason)
            if success { action() }
        }
    }

    /// Mesma ideia, para ações sobre a coleção em si (renomear, cor,
    /// excluir) — não confundir com `toggleCollectionLock`, que só pede
    /// senha pra DESATIVAR a proteção.
    private func protectedCollectionAction(_ collection: NotebookGroup, reason: String, action: @escaping () -> Void) {
        guard collection.isLocked else {
            action()
            return
        }
        Task {
            let success = await BiometricLock.authenticate(reason: reason)
            if success { action() }
        }
    }

    /// Abre o caderno direto se ele (e a coleção dele) não estiver
    /// protegido; senão pede autenticação antes de empurrar a tela.
    /// `sectionID`/`pageIndex` vêm de um resultado de busca — deixam a tela
    /// do caderno já abrir direto no lugar certo, em vez da primeira seção.
    private func openNotebook(_ notebook: Notebook, sectionID: UUID? = nil, pageIndex: Int? = nil) {
        pendingSectionID = sectionID
        pendingPageIndex = pageIndex
        protectedNotebookAction(notebook, reason: "Desbloquear o caderno \"\(notebook.title)\"") {
            path.append(notebook.id)
        }
    }

    /// Um resultado de busca tocado de DENTRO de outra tela (um caderno já
    /// aberto, a fitoteca) chega até aqui pra decidir como navegar — volta
    /// pra tela inicial primeiro (só ela tem o NavigationPath) e daí segue
    /// pro alvo, exatamente como se a busca tivesse começado por aqui.
    private func jumpElsewhere(_ target: SearchResult.Target) {
        path.removeLast(path.count)
        switch target {
        case .collection:
            break // já fica visível na tela inicial, sem navegação extra
        case .notebook(let notebook):
            openNotebook(notebook)
        case .section(let section):
            guard let notebook = section.notebook else { return }
            openNotebook(notebook, sectionID: section.id)
        case .page(let page):
            guard let section = page.section, let notebook = section.notebook else { return }
            let index = section.sortedPages.firstIndex(where: { $0.id == page.id }) ?? 0
            openNotebook(notebook, sectionID: section.id, pageIndex: index)
        case .audioMemo(let memo):
            pendingAudioMemoID = memo.id
            isShowingLibrary = true
        }
    }

    /// Recolher nunca pede senha; expandir uma coleção protegida, sim —
    /// senão os cadernos dela apareceriam na grade sem nenhuma autenticação.
    private func toggleShelf(shelfID: UUID, isExpanded: Bool, isLocked: Bool, title: String) {
        if isExpanded {
            withAnimation(.easeInOut(duration: 0.2)) {
                _ = collapsedShelfIDs.insert(shelfID)
            }
            return
        }
        guard isLocked else {
            withAnimation(.easeInOut(duration: 0.2)) {
                _ = collapsedShelfIDs.remove(shelfID)
            }
            return
        }
        Task {
            let success = await BiometricLock.authenticate(reason: "Desbloquear a coleção \"\(title)\"")
            if success {
                withAnimation(.easeInOut(duration: 0.2)) {
                    _ = collapsedShelfIDs.remove(shelfID)
                }
            }
        }
    }

    /// Ativar a proteção é imediato (quem está configurando já é o dono do
    /// aparelho); desativar exige autenticação — senão bastaria abrir o
    /// menu (visível sem nenhuma senha) e tirar a proteção livremente.
    private func toggleNotebookLock(_ notebook: Notebook) {
        if notebook.isLocked {
            Task {
                let success = await BiometricLock.authenticate(
                    reason: "Remover a proteção de \"\(notebook.title)\""
                )
                if success {
                    notebook.isLocked = false
                }
            }
        } else {
            notebook.isLocked = true
        }
    }

    private func toggleCollectionLock(_ collection: NotebookGroup) {
        if collection.isLocked {
            Task {
                let success = await BiometricLock.authenticate(
                    reason: "Remover a proteção da coleção \"\(collection.title)\""
                )
                if success {
                    collection.isLocked = false
                }
            }
        } else {
            collection.isLocked = true
            collapsedShelfIDs.insert(collection.id)
        }
    }
}

/// Chave de preferência usada só pra saber o quanto a lista de cadernos
/// rolou, e assim fazer os olhos do mascote acompanharem o scroll.
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension NotebookGroup {
    /// UUID fixo só pra identificar a estante "Outros" na UI (cadernos sem
    /// coleção) — nunca é salvo, é só a chave usada pro estado de colapsar/expandir.
    static let ungroupedShelfID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

#Preview {
    NotebookListView()
        .modelContainer(for: [Notebook.self, NotebookGroup.self, Section.self, NotebookPage.self, AudioMemo.self], inMemory: true)
}
