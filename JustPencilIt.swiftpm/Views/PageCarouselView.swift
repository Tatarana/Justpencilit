import SwiftUI

/// Navegação entre as páginas de uma seção, com a virada nativa do iOS
/// (ver PageCurlView): puxar a borda da folha com o dedo, tocar na lateral,
/// ou os botões ‹ ›.
///
/// A caneta/cor e a navegação de página aparecem como cápsulas flutuantes
/// sobre a página (em vez de barras fixas que tomam espaço permanente),
/// e podem ser escondidas com um toque pra maximizar a área de desenho.
struct PageCarouselView: View {
    @Bindable var section: Section
    @Binding var selectedPageIndex: Int
    var isActive: Bool = true
    @Binding var penKind: PenKind
    @Binding var penColor: PenColor
    /// Troca pra grade de miniaturas (ver PageGridView) — de lá dá pra
    /// selecionar várias páginas e movê-las pra outra seção.
    var onShowGrid: () -> Void = {}

    // Verdadeiro enquanto uma virada de página está acontecendo.
    @State private var isAnimating = false
    @State private var showChrome = true
    // Com a paleta do iPad, a nossa PenToolbar some (ver CanvasView).
    @AppStorage(AppSettingsKeys.useSystemToolPicker) private var useSystemToolPicker: Bool = true

    // Suavizar traços / desfazer — dois botões (ver `smoothControls`). Fica
    // aqui (e não em NotebookDetailView) porque é o próprio carrossel quem
    // sabe qual página está visível agora.
    @State private var smoothTrigger = 0
    @State private var undoTrigger = 0
    @State private var redoTrigger = 0
    // Quantos passos em sequência dá pra desfazer/refazer agora (até 20 —
    // cada traço, apagão ou suavização conta como um passo).
    @State private var undoCount = 0
    @State private var redoCount = 0

    private var pages: [NotebookPage] {
        section.sortedPages
    }

    var body: some View {
        Group {
            ZStack {
                if !pages.isEmpty {
                    PageCurlView(
                        pageIDs: pages.map(\.id),
                        selectedIndex: $selectedPageIndex,
                        content: { pageID, isCurrent in
                            pageView(pageID: pageID, isCurrent: isCurrent)
                        },
                        onTurningChange: { turning in
                            isAnimating = turning
                        }
                    )
                }

                if showChrome {
                    if useSystemToolPicker {
                        // A paleta do iPad fica embaixo e cobria a cápsula
                        // de navegação e os botões da direita — com ela, os
                        // dois sobem pro topo da folha.
                        ZStack(alignment: .top) {
                            pageNavPill
                            HStack(alignment: .top) {
                                Spacer()
                                smoothControls
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(14)
                        .transition(.opacity)
                    } else {
                        VStack {
                            HStack {
                                Spacer()
                                PenToolbar(kind: $penKind, color: $penColor)
                            }
                            Spacer()
                            ZStack {
                                pageNavPill
                                HStack {
                                    Spacer()
                                    smoothControls
                                }
                            }
                        }
                        .padding(14)
                        .transition(.opacity)
                    }
                }

                VStack {
                    HStack {
                        chromeToggleButton
                        Spacer()
                    }
                    Spacer()
                }
                .padding(14)
            }
        }
        .onChange(of: section.id) { _, _ in
            selectedPageIndex = 0
        }
        .onChange(of: selectedPageIndex) { _, _ in
            // Desfazer/refazer é só da visita à página — folha nova começa zerada.
            undoCount = 0
            redoCount = 0
        }
        .onChange(of: pages.count) { _, newCount in
            if selectedPageIndex >= newCount {
                selectedPageIndex = max(0, newCount - 1)
            }
        }
    }

    private var pageNavPill: some View {
        // Alvos de 44pt (mínimo recomendado pela Apple) — antes cada botão
        // era só do tamanho do ícone, e um toque um pouco fora caía no papel.
        HStack(spacing: 4) {
            Button(action: goToFirst) {
                Image(systemName: "backward.end.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(selectedPageIndex <= 0)
            .accessibilityLabel("Primeira página")

            Button(action: goToPrevious) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(selectedPageIndex <= 0)

            Text("\(min(selectedPageIndex + 1, pages.count))/\(pages.count)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(action: goToNext) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(selectedPageIndex >= pages.count - 1)

            Button(action: goToLast) {
                Image(systemName: "forward.end.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(selectedPageIndex >= pages.count - 1)
            .accessibilityLabel("Última página")

            Divider().frame(height: 16)

            Button(action: addPage) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }

            Button(action: onShowGrid) {
                Image(systemName: "square.grid.2x2")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .foregroundStyle(.primary)
        .background(.ultraThinMaterial, in: Capsule())
        // Toque no meio da cápsula (entre botões) não vaza pro papel.
        .contentShape(Capsule())
        .onTapGesture {}
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
    }

    /// Três botões empilhados: desfazer, refazer (memória de até 20 passos
    /// cada, mais recente primeiro) e suavizar. Desfazer/refazer ficam
    /// sempre visíveis, só esmaecidos e desabilitados quando não há nada
    /// pra fazer; com mais de um passo disponível, um numerozinho no canto
    /// mostra quantos restam.
    private var smoothControls: some View {
        VStack(spacing: 10) {
            Button {
                undoTrigger += 1
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(undoCount > 0 ? Color.orange : Color.secondary)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                    .overlay(alignment: .topTrailing) {
                        if undoCount > 1 {
                            Text("\(undoCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.orange, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(undoCount == 0)
            .opacity(undoCount == 0 ? 0.45 : 1)
            .accessibilityLabel("Desfazer")

            Button {
                redoTrigger += 1
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(redoCount > 0 ? Color.orange : Color.secondary)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                    .overlay(alignment: .topTrailing) {
                        if redoCount > 1 {
                            Text("\(redoCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.orange, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(redoCount == 0)
            .opacity(redoCount == 0 ? 0.45 : 1)
            .accessibilityLabel("Refazer")

            Button {
                smoothTrigger += 1
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.primary)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Suavizar traços")

            if let currentPage {
                Button {
                    currentPage.isFavorite.toggle()
                } label: {
                    Image(systemName: currentPage.isFavorite ? "star.fill" : "star")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(currentPage.isFavorite ? Color.yellow : Color.primary)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(currentPage.isFavorite ? "Remover dos favoritos" : "Favoritar página")

                // Marcador: o caderno passa a abrir direto nesta página.
                // Só um por caderno — marcar outra página move o marcador.
                if let notebook = section.notebook {
                    let isBookmarked = notebook.bookmarkedPageID == currentPage.id
                    Button {
                        notebook.bookmarkedPageID = isBookmarked ? nil : currentPage.id
                    } label: {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(isBookmarked ? Color.red : Color.primary)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isBookmarked ? "Tirar marcador" : "Marcar esta página")
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: undoCount)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: redoCount)
    }

    private var currentPage: NotebookPage? {
        pages.indices.contains(selectedPageIndex) ? pages[selectedPageIndex] : nil
    }

    private var chromeToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showChrome.toggle()
            }
        } label: {
            Image(systemName: showChrome ? "eye.slash" : "eye")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(.primary)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    /// Folha de uma página. As vizinhas pré-carregadas pela virada recebem
    /// contadores de desfazer "falsos" pra não zerarem os da folha atual.
    @ViewBuilder
    private func pageView(pageID: UUID, isCurrent: Bool) -> some View {
        if let page = pages.first(where: { $0.id == pageID }) {
            NotebookPageCanvas(
                page: page,
                background: section.backgroundStyle,
                isActive: isCurrent && isActive && !isAnimating,
                penKind: penKind,
                penColor: penColor,
                smoothTrigger: smoothTrigger,
                undoTrigger: undoTrigger,
                redoTrigger: redoTrigger,
                undoCount: isCurrent ? $undoCount : .constant(0),
                redoCount: isCurrent ? $redoCount : .constant(0)
            )
        } else {
            Color.clear
        }
    }

    // MARK: - Botões ‹ ›

    private func goToPrevious() {
        guard selectedPageIndex > 0, !isAnimating else { return }
        selectedPageIndex -= 1
    }

    private func goToNext() {
        guard selectedPageIndex < pages.count - 1, !isAnimating else { return }
        selectedPageIndex += 1
    }

    private func goToFirst() {
        guard selectedPageIndex > 0, !isAnimating else { return }
        selectedPageIndex = 0
    }

    private func goToLast() {
        guard selectedPageIndex < pages.count - 1, !isAnimating else { return }
        selectedPageIndex = pages.count - 1
    }

    private func addPage() {
        let newPage = NotebookPage(order: section.pages.count)
        newPage.section = section
        section.pages.append(newPage)
        selectedPageIndex = section.pages.count - 1
    }
}
