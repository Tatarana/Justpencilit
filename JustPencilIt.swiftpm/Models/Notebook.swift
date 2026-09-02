import Foundation

/// Um caderno: coleção de páginas desenhadas/escritas com a Apple Pencil.
struct Notebook: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var pageIDs: [UUID]

    init(id: UUID = UUID(), title: String, pageIDs: [UUID] = []) {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.pageIDs = pageIDs
    }
}

/// Uma página dentro de um caderno, contendo o desenho capturado via PencilKit.
struct NotebookPage: Identifiable, Codable, Hashable {
    let id: UUID
    var notebookID: UUID
    var drawingData: Data // PKDrawing serializado
    var order: Int

    init(id: UUID = UUID(), notebookID: UUID, drawingData: Data = Data(), order: Int) {
        self.id = id
        self.notebookID = notebookID
        self.drawingData = drawingData
        self.order = order
    }
}
