import SwiftUI
import SwiftData

/// Painel lateral (opção "4" discutida com o usuário): desliza da borda
/// direita e fica ao LADO do carrossel de páginas, não por cima — dá pra
/// ouvir/ler a ideia gravada enquanto se desenha na página ao lado, sem
/// perder o contexto. Mostra só os memos etiquetados com a seção do
/// caderno que está selecionada agora; ao trocar de aba de seção, o painel
/// atualiza sozinho.
struct AudioSectionPanelView: View {
    var section: Section?
    var onClose: () -> Void

    @Query(sort: \AudioMemo.createdAt, order: .reverse) private var allMemos: [AudioMemo]
    @Query private var notebooks: [Notebook]

    @State private var isShowingRecorder = false
    @State private var openedMemo: AudioMemo?

    private var memos: [AudioMemo] {
        guard let section else { return [] }
        // Este painel não tem Face ID/senha próprios — diferente da
        // fitoteca, que só revela título/duração depois de desbloquear. Pra
        // não vazar memos protegidos aqui (sem nenhuma trava própria), eles
        // simplesmente não aparecem nesta lista.
        return allMemos.filter { $0.section?.id == section.id && !$0.isProtected }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if memos.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(memos) { memo in
                            AudioMemoPanelCard(memo: memo) {
                                openedMemo = memo
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        // Material translúcido (efeito "vidro fosco") em vez de uma cor
        // sólida — dá pra ver por baixo, meio embaçado, o que está na
        // página ao lado, em vez do painel parecer uma tela separada.
        .background(.ultraThinMaterial)
        .sheet(isPresented: $isShowingRecorder) {
            AudioRecordingSheet(onFinished: {}, initialSection: section)
        }
        .sheet(item: $openedMemo) { memo in
            NavigationStack {
                AudioMemoDetailView(memo: memo, notebooks: notebooks) {
                    openedMemo = nil
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Áudios da seção")
                    .font(.headline)
                if let section {
                    Text(section.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                isShowingRecorder = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .disabled(section == nil)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(.systemBackground)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Nenhum áudio nesta seção")
                .font(.subheadline.weight(.semibold))
            Text("Grave uma ideia e ela já fica etiquetada aqui.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                isShowingRecorder = true
            } label: {
                Label("Gravar uma ideia", systemImage: "mic.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(section == nil)
            Spacer()
        }
        .padding(.horizontal, 12)
    }
}

/// Card compacto de um memo dentro do painel: play/pause + progresso, e a
/// transcrição já vem expandida embaixo — o objetivo é dar pra ler sem
/// precisar tocar em nada. O "•••" abre a tela cheia de detalhe (renomear,
/// trocar de seção, excluir).
private struct AudioMemoPanelCard: View {
    var memo: AudioMemo
    var onOpenDetail: () -> Void

    @State private var player = AudioPlayerService()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    player.togglePlayback(fileURL: AudioStore.url(for: memo.audioFileName))
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(memo.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    ProgressView(value: player.progress)
                }

                Button(action: onOpenDetail) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            transcriptView
        }
        .padding(12)
        // Cards um pouco mais opacos que o fundo do painel (senão o texto
        // da transcrição fica difícil de ler por cima do que passa atrás).
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onDisappear { player.stop() }
    }

    @ViewBuilder
    private var transcriptView: some View {
        switch memo.transcriptionStatus {
        case .pending:
            Text("Ainda não transcrito.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .transcribing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Transcrevendo…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .done:
            Text(memo.transcript ?? "")
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.85))
        case .failed:
            Text("Não deu pra transcrever esse áudio.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
