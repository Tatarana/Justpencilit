import Foundation
import PencilKit
import VisionKit
import SwiftData

/// Reconhece o texto escrito à mão numa página, usando o motor do Live Text
/// (o mesmo que sublinha texto em fotos no app Fotos/Notas) — lida bem
/// melhor com letra cursiva do que o Vision clássico (VNRecognizeTextRequest),
/// e roda inteiramente no aparelho, sem precisar de internet.
enum OCRService {
    /// Reconhece o texto de um desenho já carregado, sem mexer em nada
    /// persistido — devolve string vazia se não tiver traço nenhum ou se o
    /// reconhecimento não estiver disponível/não achar nada.
    @MainActor
    static func recognizeText(in drawing: PKDrawing) async -> String {
        guard !drawing.strokes.isEmpty else { return "" }
        let bounds = drawing.bounds.insetBy(dx: -20, dy: -20)
        guard bounds.width > 0, bounds.height > 0, ImageAnalyzer.isSupported else { return "" }

        let image = drawing.image(from: bounds, scale: 2)
        let analyzer = ImageAnalyzer()
        let configuration = ImageAnalyzer.Configuration([.text])
        do {
            let analysis = try await analyzer.analyze(image, configuration: configuration)
            return analysis.transcript
        } catch {
            return ""
        }
    }

    /// Roda o OCR de uma página específica e já grava o resultado nela
    /// (texto reconhecido, data, e limpa a flag de pendente).
    @MainActor
    static func process(_ page: NotebookPage) async {
        let drawing = DrawingStore.load(fileName: page.drawingFileName)
        let text = await recognizeText(in: drawing)
        page.recognizedText = text
        page.ocrUpdatedAt = Date()
        page.ocrDirty = false
    }

    // Evita duas varreduras rodando ao mesmo tempo (ex: app volta do 2º
    // plano bem rápido, duas vezes seguidas).
    @MainActor private static var isSweeping = false

    /// Varre todas as páginas ainda marcadas como pendentes e roda o OCR
    /// nelas, uma de cada vez — chamada ao abrir o app e ao voltar do 2º
    /// plano, pra pegar o que ficou pra trás se o app foi fechado no meio
    /// (ou se uma página nunca chegou a "perder o foco" pra disparar o OCR
    /// individual).
    @MainActor
    static func catchUpSweep(modelContext: ModelContext) async {
        guard !isSweeping else { return }
        isSweeping = true
        defer { isSweeping = false }

        let descriptor = FetchDescriptor<NotebookPage>(
            predicate: #Predicate { $0.ocrDirty == true }
        )
        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else { return }
        for page in pending {
            await process(page)
        }
    }
}
