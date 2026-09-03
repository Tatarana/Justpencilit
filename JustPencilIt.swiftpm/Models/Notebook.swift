import Foundation
import SwiftData

/// Um caderno: coleção de seções (ex: "Física", "Matemática"), cada uma com
/// suas próprias páginas. Persistido localmente via SwiftData.
@Model
final class Notebook: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    // Precisa do valor padrão aqui na própria declaração (não só no init) —
    // é o que permite ao SwiftData migrar automaticamente bancos salvos
    // antes desse campo existir, em vez de travar ao abrir o app.
    var coverColor: NotebookColor = NotebookColor.blue

    @Relationship(deleteRule: .cascade, inverse: \Section.notebook)
    var sections: [Section] = []

    init(title: String, coverColor: NotebookColor = .blue) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.coverColor = coverColor
    }

    var sortedSections: [Section] {
        sections.sorted { $0.order < $1.order }
    }
}
