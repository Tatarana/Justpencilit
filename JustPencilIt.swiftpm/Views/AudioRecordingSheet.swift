import SwiftUI
import SwiftData

/// Tela de gravação: abre já gravando (menos um toque, já que a ideia é
/// capturar rápido antes que ela escape), mostra um "VU-meter" cartoon que
/// reage ao volume da voz, e ao parar salva o memo e já dispara a
/// transcrição em segundo plano — sem precisar de mais nenhum toque.
///
/// Sempre apresentada como uma janela (`.sheet`) por cima da fitoteca
/// (`AudioLibraryView`), nunca mais em tela cheia — assim, ao fechar (seja
/// cancelando ou depois de salvar), quem gravou já está exatamente onde o
/// áudio apareceu na grade.
struct AudioRecordingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioMemo.createdAt) private var existingMemos: [AudioMemo]

    var onFinished: () -> Void
    /// Quando gravado a partir do painel de áudios de uma seção (dentro de
    /// um caderno aberto), o memo já nasce etiquetado ali — sem precisar de
    /// mais um toque pra associar depois.
    var initialSection: Section? = nil

    @State private var recorder = AudioRecorderService()
    @State private var didStart = false
    @State private var failedToStart = false
    /// Depois de parar, ficamos aqui (em vez de fechar direto) — é onde a
    /// pessoa descobre pra onde o áudio foi.
    @State private var savedMemoTitle: String?

    var body: some View {
        Group {
            if let savedMemoTitle {
                savedConfirmation(title: savedMemoTitle)
            } else {
                recordingControls
            }
        }
        .task {
            guard !didStart else { return }
            didStart = true
            let fileName = "\(UUID().uuidString).m4a"
            let started = await recorder.startRecording(fileName: fileName)
            if !started { failedToStart = true }
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 28) {
            Spacer()

            Text(recorder.isRecording ? "Gravando sua ideia…" : (failedToStart ? "Não consegui usar o microfone" : "Preparando…"))
                .font(.title3.weight(.semibold))

            WaveformView(level: recorder.meterLevel, isActive: recorder.isRecording)
                .frame(height: 80)
                .padding(.horizontal, 40)

            Text(formattedTime)
                .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 40) {
                Button {
                    recorder.cancelRecording()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2.weight(.semibold))
                        .frame(width: 56, height: 56)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }

                Button {
                    finishAndSave()
                } label: {
                    ZStack {
                        Circle().fill(Color.red)
                        RoundedRectangle(cornerRadius: 4).fill(Color.white).frame(width: 22, height: 22)
                    }
                    .frame(width: 72, height: 72)
                }
                .disabled(!recorder.isRecording)
            }
            .padding(.bottom, 40)
        }
    }

    /// Confirmação depois de salvar. Como esta tela é sempre uma janela em
    /// cima da fitoteca, fechar (o único botão daqui) já revela o áudio
    /// novinho na grade por trás — não precisa de um botão separado pra
    /// "ir" pra biblioteca, a biblioteca já está logo ali.
    private func savedConfirmation(title: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Ideia gravada!")
                .font(.title2.weight(.bold))
            Text("Salva como \"\(title)\" — transcrevendo em segundo plano.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Concluído")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    private var formattedTime: String {
        let total = Int(recorder.elapsedTime)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func finishAndSave() {
        guard let duration = recorder.stopRecording(), let fileName = recorder.pendingFileName else {
            dismiss()
            return
        }
        let title = "Ideia \(existingMemos.count + 1)"
        let memo = AudioMemo(
            title: title,
            coverColor: NotebookColor.forOrder(existingMemos.count),
            audioFileName: fileName
        )
        memo.duration = duration
        memo.section = initialSection
        modelContext.insert(memo)

        transcribe(memo)
        onFinished()
        savedMemoTitle = title
    }

    private func transcribe(_ memo: AudioMemo) {
        MemoTranscription.start(memo, in: modelContext)
    }
}

/// Barrinhas verticais que sobem e descem com o nível do áudio — mais
/// "vivo" e fácil de fazer no SwiftUI do que uma forma de onda real.
private struct WaveformView: View {
    var level: CGFloat
    var isActive: Bool

    private let barCount = 24
    @State private var seed = Double.random(in: 0...1000)

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !isActive)) { timeline in
            HStack(spacing: 4) {
                ForEach(0..<barCount, id: \.self) { index in
                    let phase = timeline.date.timeIntervalSinceReferenceDate + seed + Double(index) * 0.35
                    let wiggle = (sin(phase * 4) + 1) / 2
                    let height = 8 + (level * 60 * (0.4 + 0.6 * wiggle))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red.gradient)
                        .frame(width: 4, height: max(6, height))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}
