import Foundation
import SwiftData

/// Um grupo de cadernos — como uma "estante" (ex: Trabalho, Pessoal, RPG).
/// Excluir um grupo não apaga os cadernos dentro dele, só os deixa sem grupo
/// (por isso `deleteRule: .nullify`).
@Model
final class NotebookGroup: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var order: Int
    var color: NotebookColor = NotebookColor.blue
    // Se true, expandir esta coleção (e abrir qualquer caderno dentro dela)
    // exige Face ID/Touch ID ou a senha do iPad primeiro.
    var isLocked: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Notebook.group)
    var notebooks: [Notebook] = []

    init(title: String, order: Int, color: NotebookColor = .blue) {
        self.id = UUID()
        self.title = title
        self.order = order
        self.color = color
    }
}
