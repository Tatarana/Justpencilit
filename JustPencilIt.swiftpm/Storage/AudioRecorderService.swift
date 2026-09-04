import AVFoundation
import CoreGraphics
import Observation

/// Encapsula o `AVAudioRecorder` do sistema: pede permissão de microfone,
/// grava em `.m4a` (AAC) na pasta do `AudioStore`, e expõe estado observável
/// (gravando ou não, tempo decorrido, nível do áudio) pra UI animar o
/// "VU-meter" cartoon sem precisar poluir a view com timers e delegates.
@Observable
final class AudioRecorderService: NSObject {
    private(set) var isRecording = false
    private(set) var elapsedTime: TimeInterval = 0
    /// Nível do áudio agora, normalizado 0...1 — pra animar a forma de onda.
    private(set) var meterLevel: CGFloat = 0

    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var startDate: Date?
    private(set) var pendingFileName: String?

    /// Pede permissão de microfone (se ainda não decidida) e começa a
    /// gravar. `fileName` já vem pronto (ver `AudioMemo.audioFileName`),
    /// pra já sabermos o nome final antes mesmo de terminar de gravar.
    func startRecording(fileName: String) async -> Bool {
        let granted = await requestMicPermission()
        guard granted else { return false }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            return false
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        let fileURL = AudioStore.url(for: fileName)
        guard let recorder = try? AVAudioRecorder(url: fileURL, settings: settings) else {
            return false
        }
        recorder.isMeteringEnabled = true
        guard recorder.record() else { return false }

        self.recorder = recorder
        self.pendingFileName = fileName
        self.startDate = Date()
        self.isRecording = true
        self.elapsedTime = 0
        startMeterLoop()
        return true
    }

    /// Para a gravação e devolve a duração final — `nil` se não estava
    /// gravando (ex: chamado duas vezes).
    @discardableResult
    func stopRecording() -> TimeInterval? {
        guard let recorder, isRecording else { return nil }
        recorder.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        meterTask?.cancel()
        isRecording = false
        let finalDuration = startDate.map { Date().timeIntervalSince($0) } ?? elapsedTime
        // O AVAudioRecorder grava o arquivo sozinho (não passa por um
        // Data.write nosso), então a proteção de dados é aplicada aqui,
        // depois que ele termina de escrever.
        if let fileName = pendingFileName {
            FileProtection.apply(to: AudioStore.url(for: fileName))
        }
        self.recorder = nil
        self.startDate = nil
        return finalDuration
    }

    /// Cancela e apaga o arquivo parcial — usado quando o usuário desiste
    /// da gravação em vez de salvar.
    func cancelRecording() {
        guard let fileName = pendingFileName else { return }
        recorder?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        meterTask?.cancel()
        AudioStore.delete(fileName: fileName)
        isRecording = false
        recorder = nil
        startDate = nil
        pendingFileName = nil
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startMeterLoop() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isRecording {
                self.recorder?.updateMeters()
                if let db = self.recorder?.averagePower(forChannel: 0) {
                    // dB (tipicamente -160...0) → 0...1, com uma curva que
                    // reage bem a voz normal sem saturar em silêncio.
                    // averagePower devolve Float; meterLevel é CGFloat.
                    let normalized = CGFloat(max(0, min(1, (db + 50) / 50)))
                    await MainActor.run { self.meterLevel = normalized }
                }
                if let startDate = self.startDate {
                    await MainActor.run { self.elapsedTime = Date().timeIntervalSince(startDate) }
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }
}
