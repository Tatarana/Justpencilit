import Foundation
import SwiftData

/// Uma seção dentro de um caderno — como as divisórias de um caderno físico
/// escolar (ex: "Física", "Matemática"). Cada seção tem suas próprias páginas
/// e seu próprio estilo de fundo.
@Model
final class Section: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var order: Int
    var backgroundStyle: PageBackground
    var notebook: Notebook?

    @Relationship(deleteRule: .cascade, inverse: \NotebookPage.section)
    var pages: [NotebookPage] = []

    // Memos de áudio etiquetados com esta seção (ver AudioMemo.section) —
    // excluir a seção só remove a etiqueta, nunca apaga o áudio em si.
    @Relationship(deleteRule: .nullify, inverse: \AudioMemo.section)
    var audioMemos: [AudioMemo] = []

    init(title: String, order: Int, backgroundStyle: PageBackground = .blank) {
        self.id = UUID()
        self.title = title
        self.order = order
        self.backgroundStyle = backgroundStyle
    }

    var sortedPages: [NotebookPage] {
        pages.sorted { $0.order < $1.order }
    }

    /// Cor da aba — escolhida automaticamente pela ordem da seção, como as
    /// divisórias coloridas de um fichário.
    var tabColor: NotebookColor {
        NotebookColor.forOrder(order)
    }
}
