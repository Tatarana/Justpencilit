import Foundation
import SwiftData

/// Único caminho para transcrever um memo: gravação nova, "tentar de novo"
/// na tela do memo e fitas que chegam do celular passam todos por aqui.
/// Antes cada tela tinha a sua cópia deste código.
@MainActor
enum MemoTranscription {
    /// Memos sendo transcritos agora, para não começar duas vezes o mesmo.
    private static var running: Set<UUID> = []

    static func isRunning(_ id: UUID) -> Bool { running.contains(id) }

    /// Marca o memo como "transcrevendo" e roda em segundo plano, 100% no
    /// aparelho (`SpeechTranscriptionService`). `onFinish` roda no fim, com
    /// sucesso ou falha.
    static func start(_ memo: AudioMemo, in modelContext: ModelContext, onFinish: (() -> Void)? = nil) {
        let memoID = memo.id
        // Já transcrevendo: não começa outra; quem esperava o fim é avisado já.
        guard !MemoTranscription.running.contains(memoID) else {
            onFinish?()
            return
        }
        MemoTranscription.running.insert(memoID)
        let fileURL = AudioStore.url(for: memo.audioFileName)
        memo.transcriptionStatus = .transcribing

        Task { @MainActor in
            // Nomes qualificados: dentro do closure, nada de `self` implícito.
            defer { MemoTranscription.running.remove(memoID) }
            var text: String?
            do {
                text = try await SpeechTranscriptionService.transcribe(fileURL: fileURL)
            } catch {
                text = nil
            }

            if let memo = MemoTranscription.find(memoID, in: modelContext) {
                if let text {
                    memo.transcript = text
                    memo.transcriptionStatus = .done
                } else {
                    memo.transcriptionStatus = .failed
                }
                try? modelContext.save()

                // Fita que veio do celular: o texto volta pra lá sem esperar
                // a próxima rodada da sincronização.
                if memo.originDeviceID != nil {
                    await RelaySync.shared.publishSnapshots(modelContext: modelContext)
                }
            }
            onFinish?()
        }
    }

    private static func find(_ id: UUID, in modelContext: ModelContext) -> AudioMemo? {
        var descriptor = FetchDescriptor<AudioMemo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
