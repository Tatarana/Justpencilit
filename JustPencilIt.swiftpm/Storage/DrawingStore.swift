import Foundation
import PencilKit

/// Lê e escreve o conteúdo de um PKDrawing em disco, na pasta Documents do
/// app. Cada página vira um arquivo `.drawing` separado — mantém o SwiftData
/// leve (só metadados) e o desenho grande fora do banco.
enum DrawingStore {
    static var directory: URL {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Drawings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func load(fileName: String) -> PKDrawing {
        let fileURL = url(for: fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return PKDrawing() }
        return (try? PKDrawing(data: data)) ?? PKDrawing()
    }

    static func save(_ drawing: PKDrawing, fileName: String) {
        let fileURL = url(for: fileName)
        do {
            try drawing.dataRepresentation().write(to: fileURL, options: .atomic)
        } catch {
            print("DrawingStore: falha ao salvar \(fileName): \(error)")
        }
    }

    static func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
