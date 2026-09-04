import Foundation
import SwiftData

/// Uma página dentro de uma seção. O desenho em si (PKDrawing) NÃO fica
/// aqui dentro — só o nome do arquivo onde ele está salvo em disco
/// (ver DrawingStore). Guardar o traçado como blob dentro do banco deixaria
/// a lista de cadernos lenta pra carregar conforme os cadernos crescem.
@Model
final class NotebookPage: Identifiable {
    @Attribute(.unique) var id: UUID
    var order: Int
    var drawingFileName: String
    var updatedAt: Date
    var section: Section?

    // Texto reconhecido do que foi escrito à mão nesta página (via Live
    // Text/OCRService) — usado pela busca global. Vazio até a primeira
    // passada de reconhecimento. Precisa de valor padrão aqui na própria
    // declaração (não só no init), senão o SwiftData trava ao abrir bancos
    // salvos antes desses campos existirem.
    var recognizedText: String = ""
    var ocrUpdatedAt: Date?
    // true = o desenho mudou desde o último OCR (ou nunca rodou ainda) —
    // sinaliza que essa página precisa passar pelo OCRService de novo.
    var ocrDirty: Bool = true

    // Favoritada pra aparecer na grade de "Páginas favoritas" do caderno —
    // útil pra marcar uma página de referência (ex: um resumo, uma fórmula)
    // no meio de um caderno grande. Valor padrão na declaração pelo mesmo
    // motivo de ocrDirty acima.
    var isFavorite: Bool = false

    init(order: Int) {
        self.id = UUID()
        self.order = order
        self.drawingFileName = "\(UUID().uuidString).drawing"
        self.updatedAt = Date()
    }
}
