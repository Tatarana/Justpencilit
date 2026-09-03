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

    init(order: Int) {
        self.id = UUID()
        self.order = order
        self.drawingFileName = "\(UUID().uuidString).drawing"
        self.updatedAt = Date()
    }
}
