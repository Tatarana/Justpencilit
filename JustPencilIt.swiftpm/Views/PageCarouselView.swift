import SwiftUI

/// Navegação entre as páginas de uma seção. Duas formas de virar:
/// arrastando a página de lado com o dedo (como um livro de verdade,
/// acompanhando o dedo em tempo real) ou tocando nos botões ‹ › — que
/// disparam a mesma animação de "dobra", só sem seguir o dedo.
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

    // Ângulo de "dobra" da página — atualizado ao vivo durante o arrasto,
    // ou animado de 0 a 90 e de volta quando disparado pelos botões.
    @State private var flipAngle: Double = 0
    @State private var isAnimating = false
    @State private var showChrome = true

    // Suavizar traços / desfazer — dois botões (ver `smoothControls`). Fica
    // aqui (e não em NotebookDetailView) porque é o próprio carrossel quem
    // sabe qual página está visível agora.
    @State private var smoothTrigger = 0
    @State private var undoSmoothTrigger = 0
    // Quantas suavizações em sequência dá pra desfazer agora (até 3).
    @State private var undoSmoothCount = 0

    private var pages: [NotebookPage] {
        section.sortedPages
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if pages.indices.contains(selectedPageIndex) {
                    let page = pages[selectedPageIndex]
                    NotebookPageCanvas(
                        page: page,
                        background: section.backgroundStyle,
                        isActive: isActive && !isAnimating,
                        penKind: penKind,
                        penColor: penColor,
                        onDragChanged: { translationX in
                            handleDragChanged(translationX, width: geometry.size.width)
                        },
                        onDragEnded: { translationX, velocityX in
                            handleDragEnded(translationX, velocityX: velocityX, width: geometry.size.width)
                        },
                        smoothTrigger: smoothTrigger,
                        undoSmoothTrigger: undoSmoothTrigger,
                        undoSmoothCount: $undoSmoothCount
                    )
                    // Força a SwiftUI recriar a view (e seu @State de desenho)
                    // ao trocar de página/seção — sem isso, a view era reaproveitada
                    // na mesma posição da hierarquia e o desenho de uma página
                    // "vazava" pra outra.
                    .id(page.id)
                    // Gira em torno da borda esquerda (onde fica a espiral) em
                    // vez do centro — assim a página realmente "sai" de um
                    // canto e só depois abre pra margem oposta, como uma
                    // folha de caderno de espiral virando de verdade.
                    .rotation3DEffect(
                        .degrees(flipAngle),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .leading,
                        perspective: 0.35
                    )
                    // A página "de perfil" (perto de 90°, bem na dobra) quase
                    // não é visível numa folha real — esse esmaecimento no pico
                    // do giro deixa a virada mais fluida e menos um corte abrupto.
                    .opacity(1 - min(abs(flipAngle) / 90, 1) * 0.85)
                }

                if showChrome {
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
            flipAngle = 0
        }
        .onChange(of: pages.count) { _, newCount in
            if selectedPageIndex >= newCount {
                selectedPageIndex = max(0, newCount - 1)
            }
        }
    }

    private var pageNavPill: some View {
        HStack(spacing: 14) {
            Button(action: goToPrevious) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .disabled(selectedPageIndex <= 0)

            Text("\(min(selectedPageIndex + 1, pages.count))/\(pages.count)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(action: goToNext) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .disabled(selectedPageIndex >= pages.count - 1)

            Divider().frame(height: 16)

            Button(action: addPage) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
    }

    /// Dois botões empilhados: a varinha (suavizar) fica sempre disponível,
    /// no mesmo lugar — dá pra suavizar de novo quantas vezes quiser, sem
    /// precisar sair e voltar da página. O de desfazer só aparece por cima
    /// dela quando existe alguma suavização recente pra reverter (e some
    /// sozinho se você escrever algo novo depois de suavizar, pra não
    /// arriscar desfazer e apagar esse traço novo).
    ///
    /// Guarda até 3 suavizações em sequência: cada toque no desfazer volta
    /// uma de cada vez, da mais recente pra mais antiga. Com mais de uma
    /// disponível, um numerozinho no canto do botão mostra quantas restam.
    private var smoothControls: some View {
        VStack(spacing: 10) {
            if undoSmoothCount > 0 {
                Button {
                    undoSmoothTrigger += 1
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                        .foregroundStyle(Color.orange)
                        .overlay(alignment: .topTrailing) {
                            if undoSmoothCount > 1 {
                                Text("\(undoSmoothCount)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Color.orange, in: Circle())
                                    .offset(x: 6, y: -6)
                            }
                        }
                }
                .transition(.scale.combined(with: .opacity))
            }

            Button {
                smoothTrigger += 1
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: undoSmoothCount)
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
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        }
    }

    // MARK: - Arrastar com o dedo

    private func handleDragChanged(_ translationX: CGFloat, width: CGFloat) {
        guard !isAnimating, width > 0 else { return }
        // Arrastar pra esquerda pede a próxima página; pra direita, a anterior.
        // Se não houver pra onde ir, nem acompanha o dedo (sem "elástico" por enquanto).
        if translationX < 0 && selectedPageIndex >= pages.count - 1 { return }
        if translationX > 0 && selectedPageIndex <= 0 { return }
        let fraction = min(abs(translationX) / width, 1)
        flipAngle = (translationX < 0 ? -1.0 : 1.0) * fraction * 90
    }

    private func handleDragEnded(_ translationX: CGFloat, velocityX: CGFloat, width: CGFloat) {
        guard !isAnimating, width > 0, flipAngle != 0 else { return }
        let fraction = abs(translationX) / width
        let isFastFlick = abs(velocityX) > 600
        let direction: Double = translationX < 0 ? 1 : -1

        if fraction > 0.35 || isFastFlick {
            completeFlip(direction: direction)
        } else {
            snapBack()
        }
    }

    private func snapBack() {
        withAnimation(.easeOut(duration: 0.22)) {
            flipAngle = 0
        }
    }

    // MARK: - Botões ‹ ›

    private func goToPrevious() {
        guard selectedPageIndex > 0, !isAnimating else { return }
        completeFlip(direction: -1)
    }

    private func goToNext() {
        guard selectedPageIndex < pages.count - 1, !isAnimating else { return }
        completeFlip(direction: 1)
    }

    /// Termina a "dobra" da página no sentido dado: gira o resto do caminho
    /// até 90° (ou parte de onde o arrasto parou), troca o conteúdo no ponto
    /// de maior giro (onde ela fica de perfil, quase invisível), e gira a
    /// nova página de volta pro lugar. Usa a variante de `withAnimation` com
    /// `completion` pra garantir que a troca de conteúdo aconteça exatamente
    /// quando a primeira metade termina, sem dessincronizar.
    private func completeFlip(direction: Double) {
        isAnimating = true
        let newIndex = selectedPageIndex + Int(direction)
        withAnimation(.easeIn(duration: 0.22)) {
            flipAngle = -90 * direction
        } completion: {
            selectedPageIndex = newIndex
            flipAngle = 90 * direction
            withAnimation(.easeOut(duration: 0.28)) {
                flipAngle = 0
            } completion: {
                isAnimating = false
            }
        }
    }

    private func addPage() {
        let newPage = NotebookPage(order: section.pages.count)
        newPage.section = section
        section.pages.append(newPage)
        selectedPageIndex = section.pages.count - 1
    }
}
