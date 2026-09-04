import SwiftUI
import SwiftData

/// A "fitoteca": biblioteca central de todos os memos de áudio, em forma de
/// grade de fitas cassete. Tela cheia (não mais uma janelinha) — com
/// potencialmente muitos áudios, merece o espaço todo — com um fundo
/// ilustrado no mesmo espírito do fundo da tela principal, só que com
/// microfones, gravadores e aparelhos de som. É daqui, tocando no
/// rádio-gravador desta tela, que se abre uma nova gravação (como janela,
/// por cima desta grade). Memos etiquetados com um caderno/coleção
/// protegidos ficam escondidos até autenticar — mesma trava usada nos
/// cadernos.
struct AudioLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioMemo.createdAt, order: .reverse) private var memos: [AudioMemo]
    @Query private var notebooks: [Notebook]

    // Preenchido quando se chega aqui vindo de um resultado de busca — abre
    // esse memo automaticamente (respeitando a mesma trava de Face ID/senha
    // de sempre, se ele estiver protegido).
    var initialMemoID: UUID? = nil
    // Chamado quando a busca daqui de dentro aponta pra algo que não é um
    // áudio (um caderno, uma seção, uma página, uma coleção) — fecha esta
    // tela e deixa quem a abriu (NotebookListView) decidir como navegar.
    var onJumpElsewhere: (SearchResult.Target) -> Void = { _ in }

    @State private var path = NavigationPath()
    @State private var unlockedMemoIDs: Set<UUID> = []
    @State private var isShowingRecorder = false
    @State private var isShowingSearch = false

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 4)]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .topTrailing) {
                AudioLibraryBackgroundView(memoCount: memos.count)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    if memos.isEmpty {
                        ContentUnavailableView(
                            "Nenhuma ideia gravada ainda",
                            systemImage: "waveform",
                            description: Text("Toque no rádio-gravador aqui em cima pra registrar uma.")
                        )
                        .padding(.top, 40)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(memos) { memo in
                                    Button {
                                        open(memo)
                                    } label: {
                                        AudioMemoCoverView(memo: memo)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                        }
                    }
                }

                RadioRecorderButton {
                    isShowingRecorder = true
                }
                .padding(.top, 64)
                .padding(.trailing, 18)

                // Mesmo ícone e posição da lupa da tela inicial (canto
                // inferior esquerdo), pra ser sempre o mesmo gesto em
                // qualquer tela do app.
                VStack {
                    Spacer()
                    HStack {
                        searchButton
                        Spacer()
                    }
                }
                .padding(24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { memoID in
                if let memo = memos.first(where: { $0.id == memoID }) {
                    AudioMemoDetailView(memo: memo, notebooks: notebooks) {
                        path.removeLast(path.count)
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingRecorder) {
            // A grade (@Query) já atualiza sozinha quando o memo é salvo —
            // não precisa de nenhum gatilho extra aqui.
            AudioRecordingSheet {}
        }
        .fullScreenCover(isPresented: $isShowingSearch) {
            SearchView(
                onSelectCollection: { collection in handleSearchSelection(.collection(collection)) },
                onSelectNotebook: { notebook in handleSearchSelection(.notebook(notebook)) },
                onSelectSection: { section in handleSearchSelection(.section(section)) },
                onSelectPage: { page in handleSearchSelection(.page(page)) },
                onSelectAudioMemo: { memo in handleSearchSelection(.audioMemo(memo)) }
            )
        }
        .onAppear {
            guard let initialMemoID, let memo = memos.first(where: { $0.id == initialMemoID }) else { return }
            open(memo)
        }
    }

    /// Resultado de busca tocado dentro da fitoteca: outro áudio abre direto
    /// aqui mesmo; qualquer outra coisa (caderno, seção, página, coleção)
    /// fecha esta tela e delega a navegação pra quem a abriu.
    private func handleSearchSelection(_ target: SearchResult.Target) {
        isShowingSearch = false
        switch target {
        case .audioMemo(let memo):
            open(memo)
        default:
            dismiss()
            onJumpElsewhere(target)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle().strokeBorder(Color.black, lineWidth: 2.5)
                Image(systemName: "recordingtape")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 0) {
                Text("Ideias Faladas")
                    .font(.system(.title, design: .rounded).weight(.heavy))
                if !memos.isEmpty {
                    Text("\(memos.count) \(memos.count == 1 ? "áudio" : "áudios")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .accessibilityLabel("Fechar")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
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

    private func open(_ memo: AudioMemo) {
        guard memo.isProtected, !unlockedMemoIDs.contains(memo.id) else {
            path.append(memo.id)
            return
        }
        Task {
            let success = await BiometricLock.authenticate(reason: "Desbloquear \"\(memo.title)\"")
            if success {
                unlockedMemoIDs.insert(memo.id)
                path.append(memo.id)
            }
        }
    }
}

/// Fundo cheio de tela pra fitoteca, no mesmo espírito do fundo da tela
/// principal (papel + itens flutuando bem de leve) — só que aqui os itens
/// são do mundo do áudio: microfones, gravadores, caixas de som, antena.
private struct AudioLibraryBackgroundView: View {
    var memoCount: Int

    private struct Item {
        let symbol: String
        let size: CGFloat
        let baseX: CGFloat
        let baseY: CGFloat
        let speed: Double
        let phase: Double
        let amplitude: CGFloat
        let color: Color
    }

    private let items: [Item] = [
        Item(symbol: "mic.fill", size: 48, baseX: 0.1, baseY: 0.13, speed: 0.32, phase: 0.3, amplitude: 16, color: .red),
        Item(symbol: "hifispeaker.fill", size: 38, baseX: 0.86, baseY: 0.09, speed: 0.26, phase: 1.5, amplitude: 13, color: .indigo),
        Item(symbol: "waveform", size: 36, baseX: 0.3, baseY: 0.36, speed: 0.46, phase: 2.2, amplitude: 15, color: .orange),
        Item(symbol: "recordingtape", size: 46, baseX: 0.7, baseY: 0.42, speed: 0.24, phase: 0.8, amplitude: 17, color: .brown),
        Item(symbol: "speaker.wave.3.fill", size: 36, baseX: 0.12, baseY: 0.68, speed: 0.3, phase: 3.0, amplitude: 13, color: .teal),
        Item(symbol: "antenna.radiowaves.left.and.right", size: 30, baseX: 0.92, baseY: 0.6, speed: 0.28, phase: 1.1, amplitude: 12, color: .purple),
        Item(symbol: "music.mic", size: 40, baseX: 0.46, baseY: 0.18, speed: 0.4, phase: 1.9, amplitude: 12, color: .pink),
        Item(symbol: "headphones", size: 44, baseX: 0.58, baseY: 0.85, speed: 0.27, phase: 0.5, amplitude: 15, color: .blue),
        Item(symbol: "mic.circle.fill", size: 34, baseX: 0.0, baseY: 0.42, speed: 0.36, phase: 2.6, amplitude: 11, color: .mint),
        Item(symbol: "hifispeaker.2.fill", size: 36, baseX: 0.4, baseY: 0.62, speed: 0.22, phase: 1.3, amplitude: 14, color: .cyan),
        Item(symbol: "waveform.circle.fill", size: 32, baseX: 0.79, baseY: 0.26, speed: 0.34, phase: 0.1, amplitude: 11, color: .green),
        Item(symbol: "airpodsmax", size: 38, baseX: 0.2, baseY: 0.92, speed: 0.25, phase: 2.9, amplitude: 13, color: .gray),
        Item(symbol: "music.note", size: 30, baseX: 0.62, baseY: 0.04, speed: 0.5, phase: 0.7, amplitude: 10, color: .yellow),
        Item(symbol: "music.quarternote.3", size: 34, baseX: 0.94, baseY: 0.88, speed: 0.3, phase: 1.7, amplitude: 13, color: .indigo),
        Item(symbol: "speaker.wave.2.fill", size: 32, baseX: 0.04, baseY: 0.04, speed: 0.38, phase: 3.4, amplitude: 11, color: .red),
        Item(symbol: "waveform", size: 26, baseX: 0.5, baseY: 0.94, speed: 0.44, phase: 2.0, amplitude: 10, color: .purple),
        Item(symbol: "speaker.wave.1.fill", size: 28, baseX: 0.24, baseY: 0.24, speed: 0.42, phase: 1.2, amplitude: 10, color: .orange),
        Item(symbol: "music.note.list", size: 30, baseX: 0.68, baseY: 0.68, speed: 0.29, phase: 2.5, amplitude: 12, color: .green),
        Item(symbol: "waveform.path", size: 26, baseX: 0.88, baseY: 0.4, speed: 0.33, phase: 0.9, amplitude: 11, color: .teal),
        Item(symbol: "airpods", size: 30, baseX: 0.02, baseY: 0.82, speed: 0.31, phase: 1.6, amplitude: 12, color: .gray),
        Item(symbol: "mic", size: 26, baseX: 0.35, baseY: 0.5, speed: 0.37, phase: 3.2, amplitude: 10, color: .pink),
        Item(symbol: "waveform.badge.mic", size: 28, baseX: 0.78, baseY: 0.78, speed: 0.35, phase: 0.4, amplitude: 11, color: .indigo)
    ]

    /// Mais áudios na fitoteca, mais discreto o fundo fica (mesma lógica
    /// usada na tela principal), pra não competir com a grade de capas.
    private var presence: Double {
        let raw = 1.0 - Double(memoCount) * 0.03
        return min(1.0, max(0.32, raw))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Mesmo tom "papel" da tela principal (ver
                // MascotBackgroundView.SketchPaperImage), só que mais escuro
                // — dá mais contraste pros elementos flutuantes.
                Color(red: 0.87, green: 0.83, blue: 0.74)

                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        let x = item.baseX * geometry.size.width + CGFloat(cos(t * item.speed + item.phase)) * item.amplitude
                        let y = item.baseY * geometry.size.height + CGFloat(sin(t * item.speed + item.phase)) * item.amplitude
                        let rotation = sin(t * item.speed + item.phase) * 10

                        Image(systemName: item.symbol)
                            .font(.system(size: item.size, weight: .semibold))
                            .foregroundStyle(item.color.opacity(0.32))
                            .rotationEffect(.degrees(rotation))
                            .position(x: x, y: y)
                    }
                }
                .opacity(presence)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
