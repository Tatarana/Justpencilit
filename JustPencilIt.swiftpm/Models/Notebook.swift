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
    // Grupo/estante ao qual esse caderno pertence (ex: Trabalho, Pessoal,
    // RPG). Opcional — um caderno pode ficar sem grupo.
    var group: NotebookGroup?
    // Se true, abrir este caderno exige Face ID/Touch ID ou a senha do
    // iPad primeiro (ver BiometricLock). Valor padrão aqui na declaração
    // (não só no init) permite ao SwiftData migrar bancos salvos antes
    // desse campo existir.
    var isLocked: Bool = false
    // Favoritado pra aparecer na estante "Favoritos" no topo da tela
    // inicial, sem precisar navegar pelas coleções. Valor padrão aqui na
    // declaração (não só no init) pelo mesmo motivo de isLocked acima.
    var isFavorite: Bool = false
    // Marcador de página: a página onde o caderno abre direto. Só um por
    // caderno. Opcional com padrão nil — migra bancos antigos sem travar.
    var bookmarkedPageID: UUID? = nil
    // Tipo de papel das seções novas deste caderno. nil = segue o padrão
    // geral dos Ajustes. Opcional com padrão nil pelo mesmo motivo acima.
    var defaultBackground: PageBackground? = nil

    @Relationship(deleteRule: .cascade, inverse: \Section.notebook)
    var sections: [Section] = []

    init(title: String, coverColor: NotebookColor = .blue) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.coverColor = coverColor
    }

    /// Papel que uma seção nova deste caderno deve usar.
    var effectiveDefaultBackground: PageBackground {
        defaultBackground ?? PageBackground.appDefault
    }

    var sortedSections: [Section] {
        sections.sorted { $0.order < $1.order }
    }
}
