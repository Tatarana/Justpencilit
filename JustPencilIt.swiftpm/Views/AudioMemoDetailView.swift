import SwiftUI
import SwiftData
import AVFoundation
import Observation

/// Tela de um memo: tocar o áudio, ler (ou tentar de novo) a transcrição,
/// renomear, etiquetar com uma seção de caderno, ou excluir.
struct AudioMemoDetailView: View {
    @Bindable var memo: AudioMemo
    /// Todos os cadernos, pra montar o menu de "associar a uma seção"
    /// agrupado por caderno.
    var notebooks: [Notebook]
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var player = AudioPlayerService()
    @State private var isRenaming = false
    @State private var isDeleting = false
    @State private var isRetrying = false

    var body: some View {
        // Nada de Form/List aqui: mesmo escondendo o fundo deles
        // (.scrollContentBackground(.hidden)), o iOS insiste em pintar um
        // fundo praticamente opaco por baixo das linhas. Um ScrollView com
        // cards manuais dá controle total sobre o visual — o vidro fosco
        // (testado nesta tela e na de gravação) não se mostrou confiável
        // como janela de verdade, então aqui ficou com cores sólidas.
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                playerCard
                transcriptCard
                organizationCard
                deleteCard
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Memo de áudio")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
        .sheet(isPresented: $isRenaming) {
            RenameSheet(
                originalTitle: memo.title,
                fieldLabel: "Nome do memo",
                navigationTitleText: "Renomear memo"
            ) { newTitle in
                memo.title = newTitle
            }
        }
        .alert("Excluir \"\(memo.title)\"?", isPresented: $isDeleting) {
            Button("Cancelar", role: .cancel) {}
            Button("Excluir", role: .destructive) {
                AudioStore.delete(fileName: memo.audioFileName)
                modelContext.delete(memo)
                onDelete()
                dismiss()
            }
        } message: {
            Text("Isso apaga o áudio e a transcrição. Não dá pra desfazer.")
        }
    }

    private var playerCard: some View {
        HStack(spacing: 16) {
            Button {
                player.togglePlayback(fileURL: AudioStore.url(for: memo.audioFileName))
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(memo.title)
                    .font(.headline)
                ProgressView(value: player.progress)
                Text(formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyled()
    }

    @ViewBuilder
    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcrição")
                .font(.headline)
            switch memo.transcriptionStatus {
            case .pending:
                Text("Ainda não transcrito.")
                    .foregroundStyle(.secondary)
            case .transcribing:
                HStack {
                    ProgressView()
                    Text("Transcrevendo…")
                }
            case .done:
                Text(memo.transcript ?? "")
            case .failed:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Não deu pra transcrever esse áudio.")
                        .foregroundStyle(.secondary)
                    Button {
                        retryTranscription()
                    } label: {
                        Label(isRetrying ? "Tentando…" : "Tentar de novo", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRetrying)
                }
            }
        }
        .cardStyled()
    }

    private var organizationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Organização")
                .font(.headline)
            Button {
                isRenaming = true
            } label: {
                Label("Renomear", systemImage: "pencil")
            }
            sectionPickerMenu
        }
        .cardStyled()
    }

    /// Menu separado do resto — agrupar cadernos com `Menu` aninhado dentro
    /// de um `ForEach` é bastante coisa pro type-checker resolver de uma
    /// vez só junto com o resto da tela.
    private var sectionPickerMenu: some View {
        Menu {
            Button {
                memo.section = nil
            } label: {
                if memo.section == nil {
                    Label("Nenhuma", systemImage: "checkmark")
                } else {
                    Text("Nenhuma")
                }
            }
            ForEach(notebooks) { notebook in
                Menu(notebook.title) {
                    ForEach(notebook.sortedSections) { section in
                        Button {
                            memo.section = section
                        } label: {
                            if memo.section?.id == section.id {
                                Label(section.title, systemImage: "checkmark")
                            } else {
                                Text(section.title)
                            }
                        }
                    }
                }
            }
        } label: {
            Label(sectionPickerLabel, systemImage: "folder")
        }
    }

    /// "Caderno : Seção" quando etiquetado — só o nome da seção não dizia
    /// muita coisa sozinho, já que o mesmo nome de seção pode existir em
    /// cadernos diferentes.
    private var sectionPickerLabel: String {
        guard let section = memo.section else { return "Associar a um caderno" }
        let notebookTitle = section.notebook?.title ?? "?"
        return "\(notebookTitle) : \(section.title)"
    }

    private var deleteCard: some View {
        Button(role: .destructive) {
            isDeleting = true
        } label: {
            Label("Excluir memo", systemImage: "trash")
        }
        .cardStyled()
    }

    private var formattedDuration: String {
        let total = Int(memo.duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func retryTranscription() {
        isRetrying = true
        memo.transcriptionStatus = .transcribing
        Task {
            let fileURL = AudioStore.url(for: memo.audioFileName)
            do {
                let text = try await SpeechTranscriptionService.transcribe(fileURL: fileURL)
                await MainActor.run {
                    memo.transcript = text
                    memo.transcriptionStatus = .done
                    isRetrying = false
                }
            } catch {
                await MainActor.run {
                    memo.transcriptionStatus = .failed
                    isRetrying = false
                }
            }
        }
    }
}

private extension View {
    /// Card padrão desta tela.
    func cardStyled() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Tocador simples: play/pause e progresso 0...1, atualizado por um timer
/// leve enquanto toca (o `AVAudioPlayer` não tem um jeito nativo observável
/// de reportar o tempo atual).
@Observable
final class AudioPlayerService: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    private(set) var progress: Double = 0

    private var player: AVAudioPlayer?
    private var progressTask: Task<Void, Never>?

    func togglePlayback(fileURL: URL) {
        if isPlaying {
            pause()
            return
        }
        if player == nil || player?.url != fileURL {
            player = try? AVAudioPlayer(contentsOf: fileURL)
            player?.delegate = self
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        isPlaying = true
        startProgressLoop()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        progressTask?.cancel()
    }

    func stop() {
        player?.stop()
        isPlaying = false
        progressTask?.cancel()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.progress = 0
            self.progressTask?.cancel()
        }
    }

    private func startProgressLoop() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isPlaying {
                if let player = self.player, player.duration > 0 {
                    await MainActor.run { self.progress = player.currentTime / player.duration }
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }
}
