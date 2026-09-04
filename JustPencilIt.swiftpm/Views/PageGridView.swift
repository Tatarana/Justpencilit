import SwiftUI
import PencilKit
import UniformTypeIdentifiers

/// O que viaja quando uma página é arrastada — um ou mais ids de página
/// (mais de um quando a pessoa já tinha selecionado várias na grade antes de
/// arrastar). Só precisa fazer sentido dentro do próprio app, então usa o
/// tipo `.json` do sistema em vez de declarar um Uniform Type próprio.
struct PageDragPayload: Codable, Transferable {
    var pageIDs: [String]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// Grade com miniaturas de todas as páginas da seção aberta — a alternativa
/// ao carrossel pra quando dá pra querer ver o conjunto inteiro, selecionar
/// uma ou várias páginas de uma vez, e movê-las pra outra seção do mesmo
/// caderno: pelo botão "Mover para" (várias de uma vez) ou arrastando
/// direto pra uma das abas lá em cima (uma de cada vez, ou o grupo inteiro
/// se já estiver selecionado).
struct PageGridView: View {
    @Bindable var section: Section
    var otherSections: [Section]
    var onOpenPage: (Int) -> Void
    var onMovePages: (Set<UUID>, Section) -> Void
    /// Exporta as páginas selecionadas como um PDF — quem constrói esta tela
    /// (NotebookDetailView) decide como gerar o arquivo e como oferecer o
    /// compartilhamento, já que é ali que mora a checagem de proteção do
    /// caderno.
    var onExportPages: (Set<UUID>) -> Void = { _ in }
    /// Apaga as páginas selecionadas — quem constrói esta tela decide como
    /// remover de fato (arquivo em disco + registro), já confirmado aqui
    /// antes de chamar (ver `isConfirmingDelete`).
    var onDeletePages: (Set<UUID>) -> Void = { _ in }
    /// Fecha a grade e volta pro carrossel — usado pelo botão de voltar do
    /// cabeçalho, já que o botão de voltar padrão da tela (canto superior
    /// esquerdo) fica reservado pra sair do caderno inteiro.
    var onClose: () -> Void = {}

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var targetedPageID: UUID?
    @State private var isConfirmingDelete = false
    // Filtro "só favoritas" — não mexe na ordem/posição real das páginas
    // (isso continua vindo de `section.sortedPages`), só esconde as que não
    // estão marcadas, pra achar rápido uma página de referência num caderno
    // grande.
    @State private var showFavoritesOnly = false

    private var allPages: [NotebookPage] {
        section.sortedPages
    }

    private var pages: [NotebookPage] {
        showFavoritesOnly ? allPages.filter(\.isFavorite) : allPages
    }

    private var hasFavorites: Bool {
        allPages.contains { $0.isFavorite }
    }

    private var pageCountLabel: String {
        showFavoritesOnly ? "\(pages.count) favorita(s)" : "\(pages.count) página(s)"
    }

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(pages) { page in
                        // O número mostrado e o índice usado pra abrir no
                        // carrossel sempre vêm da posição REAL da página no
                        // caderno (`allPages`), não da posição dentro da
                        // lista filtrada — senão, com "só favoritas" ativo,
                        // "página 1" abriria a primeira página do caderno
                        // errada (a primeira FAVORITA, não a primeira de
                        // verdade).
                        let realIndex = allPages.firstIndex(where: { $0.id == page.id }) ?? 0
                        PageThumbnailCell(
                            page: page,
                            pageNumber: realIndex + 1,
                            isSelecting: isSelecting,
                            isSelected: selectedIDs.contains(page.id),
                            isDropTargeted: targetedPageID == page.id,
                            onToggleFavorite: { page.isFavorite.toggle() }
                        )
                        .draggable(dragPayload(for: page))
                        .dropDestination(for: PageDragPayload.self) { payloads, _ in
                            let ids = payloads.flatMap { $0.pageIDs }
                            guard !ids.isEmpty else { return false }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                reorderPages(ids: ids, before: page)
                            }
                            return true
                        } isTargeted: { targeted in
                            targetedPageID = targeted ? page.id : nil
                        }
                        .onTapGesture {
                            handleTap(page: page, index: realIndex)
                        }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                                handleLongPress(page: page)
                            }
                        )
                    }
                }
                .padding(16)
            }

            if isSelecting {
                selectionToolbar
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.primary)

            Text(isSelecting ? "\(selectedIDs.count) selecionada(s)" : pageCountLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            Spacer()

            if hasFavorites && !isSelecting {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFavoritesOnly.toggle()
                    }
                } label: {
                    Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                        .foregroundStyle(showFavoritesOnly ? Color.yellow : Color.primary)
                }
                .accessibilityLabel(showFavoritesOnly ? "Mostrar todas as páginas" : "Mostrar só favoritas")
                .padding(.trailing, 4)
            }

            Button(isSelecting ? "Cancelar" : "Selecionar") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelecting.toggle()
                    selectedIDs.removeAll()
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var selectionToolbar: some View {
        HStack {
            Menu {
                ForEach(otherSections) { target in
                    Button(target.title) {
                        onMovePages(selectedIDs, target)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelecting = false
                            selectedIDs.removeAll()
                        }
                    }
                }
            } label: {
                Label("Mover para…", systemImage: "folder")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .foregroundStyle(.primary)
            .disabled(selectedIDs.isEmpty || otherSections.isEmpty)

            Divider().frame(height: 20)

            Button {
                onExportPages(selectedIDs)
            } label: {
                Label("Exportar (PDF)", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .foregroundStyle(.primary)
            .disabled(selectedIDs.isEmpty)

            Divider().frame(height: 20)

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Apagar", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .foregroundStyle(.red)
            // Nunca deixa apagar TODAS as páginas da seção de uma vez —
            // sempre precisa sobrar pelo menos uma, mesma regra do apagar
            // a página atual no carrossel.
            .disabled(selectedIDs.isEmpty || selectedIDs.count >= allPages.count)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .alert(
            "Apagar \(selectedIDs.count) página(s)?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) {
                onDeletePages(selectedIDs)
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelecting = false
                    selectedIDs.removeAll()
                }
            }
        } message: {
            Text("Não dá pra desfazer — o conteúdo dessas páginas é perdido.")
        }
    }

    /// Toque numa página: fora do modo de seleção, abre ela no carrossel;
    /// dentro dele, alterna se está marcada.
    private func handleTap(page: NotebookPage, index: Int) {
        if isSelecting {
            if selectedIDs.contains(page.id) {
                selectedIDs.remove(page.id)
            } else {
                selectedIDs.insert(page.id)
            }
        } else {
            onOpenPage(index)
        }
    }

    /// Toque longo: liga o modo de seleção (se ainda não estava) e já marca
    /// a página tocada — sem precisar tocar duas vezes.
    private func handleLongPress(page: NotebookPage) {
        if !isSelecting {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSelecting = true
            }
        }
        selectedIDs.insert(page.id)
    }

    /// Se a página arrastada já fazia parte da seleção atual, arrasta o
    /// grupo inteiro junto; senão, arrasta só ela.
    private func dragPayload(for page: NotebookPage) -> PageDragPayload {
        if isSelecting, selectedIDs.contains(page.id), selectedIDs.count > 1 {
            return PageDragPayload(pageIDs: selectedIDs.map(\.uuidString))
        }
        return PageDragPayload(pageIDs: [page.id.uuidString])
    }

    /// Reordena páginas dentro desta mesma seção: solta uma (ou várias, se
    /// já selecionadas) logo antes da página alvo. Se os ids soltos não
    /// pertencerem a esta seção (veio de outra aba), não faz nada — esse
    /// caso é tratado por `onMovePages`/o drop nas abas, não aqui.
    private func reorderPages(ids: [String], before target: NotebookPage) {
        let draggedIDs = Set(ids.compactMap { UUID(uuidString: $0) })
        guard !draggedIDs.isEmpty, !draggedIDs.contains(target.id) else { return }

        // Sempre reordena a lista REAL (todas as páginas), mesmo com o
        // filtro "só favoritas" ativo — senão soltar uma página nessa vista
        // filtrada bagunçaria a ordem das páginas que ficaram escondidas.
        var ordered = allPages
        let dragged = ordered.filter { draggedIDs.contains($0.id) }
        guard !dragged.isEmpty, dragged.count == draggedIDs.count else { return }

        ordered.removeAll { draggedIDs.contains($0.id) }
        guard let targetIndex = ordered.firstIndex(where: { $0.id == target.id }) else { return }
        ordered.insert(contentsOf: dragged, at: targetIndex)

        for (index, page) in ordered.enumerated() {
            page.order = index
        }
    }
}

/// Uma miniatura: o desenho real da página (renderizado uma vez e cacheado),
/// sobre o tom de papel do fundo da seção, com o número da página embaixo e
/// um selo de seleção no canto quando a grade está em modo de seleção.
private struct PageThumbnailCell: View {
    var page: NotebookPage
    var pageNumber: Int
    var isSelecting: Bool
    var isSelected: Bool
    /// Verdadeiro enquanto outra página está sendo arrastada por cima desta,
    /// prestes a ser solta aqui (reordena pra antes desta página).
    var isDropTargeted: Bool = false
    var onToggleFavorite: () -> Void = {}

    @State private var thumbnail: UIImage?

    private let aspect: CGFloat = 0.72

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(PageBackground.paperColor))
                    .aspectRatio(aspect, contentMode: .fit)
                    .overlay {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(6)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isDropTargeted ? Color.accentColor : (isSelected ? Color.accentColor : Color.black.opacity(0.15)),
                                lineWidth: isDropTargeted ? 3.5 : (isSelected ? 3 : 1)
                            )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .scaleEffect(isDropTargeted ? 1.05 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDropTargeted)

                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                        .padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                // Estrela no canto oposto ao selo de seleção — um toque
                // aqui favorita/desfavorita na hora, sem entrar no modo de
                // seleção nem abrir a página.
                if page.isFavorite || !isSelecting {
                    Button(action: onToggleFavorite) {
                        Image(systemName: page.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(page.isFavorite ? Color.yellow : Color.white)
                            .padding(6)
                            .background(Color.black.opacity(0.35), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }

            Text("\(pageNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .task {
            let drawing = DrawingStore.load(fileName: page.drawingFileName)
            let bounds = drawing.bounds.isEmpty
                ? CGRect(x: 0, y: 0, width: 400, height: 560)
                : drawing.bounds.insetBy(dx: -20, dy: -20)
            // Mesma causa do "traço invisível" já resolvida no export de
            // PDF: a tinta da CANETA se adapta sozinha ao modo claro/escuro
            // "atual" na hora de renderizar (pra sempre contrastar com o
            // fundo) — e fora de uma tela ao vivo isso não tem contexto
            // nenhum, saindo branco sobre o papel claro da miniatura. O
            // marcador não tem esse comportamento adaptativo, por isso só
            // ele aparecia. Força-se o modo claro só durante esta
            // renderização, igual já fazemos no PDFExportService.
            var rendered = UIImage()
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                rendered = drawing.image(from: bounds, scale: 0.35)
            }
            thumbnail = rendered
        }
    }
}
