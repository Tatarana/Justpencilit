import Speech
import AVFoundation

enum TranscriptionError: Error {
    /// O idioma pedido não é suportado pelo SpeechTranscriber neste aparelho.
    case localeUnavailable
    /// A transcrição terminou sem produzir nenhum texto (ex: áudio mudo).
    case emptyResult
}

/// Transcreve um arquivo de áudio já gravado usando o `SpeechAnalyzer` +
/// `SpeechTranscriber` (iOS 26+), 100% no aparelho — sem o limite de ~1
/// minuto por sessão que o `SFSpeechRecognizer` antigo tinha, o que é
/// exatamente o que precisamos pra memos de voz que podem passar de um
/// minuto.
///
/// Nota: esta é uma API bem nova da Apple (anunciada na WWDC 2025). Se o
/// Swift Playgrounds acusar algum nome diferente do esperado aqui, é sinal
/// de que a assinatura mudou numa atualização do SDK — me avisa o erro
/// exato que eu ajusto.
enum SpeechTranscriptionService {
    static func transcribe(fileURL: URL, locale: Locale = Locale(identifier: "pt-BR")) async throws -> String {
        guard let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionError.localeUnavailable
        }

        let transcriber = SpeechTranscriber(locale: resolvedLocale, preset: .transcription)

        // Garante que o "pacote" de idioma está baixado no aparelho antes de
        // transcrever — a primeira vez pode demorar um pouco (baixa em
        // segundo plano), as próximas já usam o que já foi instalado.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: fileURL)

        // Consome o texto (via transcriber.results) ao mesmo tempo em que
        // o analyzer processa o arquivo — as duas coisas rodam em paralelo,
        // então usamos `async let` pra não travar uma esperando a outra.
        async let collectedText = collectText(from: transcriber)

        // analyzeSequence devolve o CMTime do fim do processamento — não
        // precisamos do valor, só de esperar terminar.
        _ = try await analyzer.analyzeSequence(from: audioFile)
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let fullText = try await collectedText
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.emptyResult }
        return trimmed
    }

    private static func collectText(from transcriber: SpeechTranscriber) async throws -> String {
        // Cada item da sequência é um trecho (frase/segmento) já finalizado,
        // não o texto acumulado até ali — por isso concatenamos em vez de
        // substituir. Substituir era o bug: num áudio com vários segmentos,
        // só a última frase sobrevivia, dando a impressão de que só "as
        // últimas palavras" tinham sido transcritas.
        var pieces: [String] = []
        for try await result in transcriber.results {
            let piece = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
        }
        return pieces.joined(separator: " ")
    }
}
