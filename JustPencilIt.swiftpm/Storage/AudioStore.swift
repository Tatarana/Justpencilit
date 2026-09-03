import Foundation

/// Onde os arquivos `.m4a` dos memos de áudio ficam guardados em disco —
/// mesmo padrão do `DrawingStore`: metadados no SwiftData, arquivo grande
/// fora do banco.
enum AudioStore {
    static var directory: URL {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioMemos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
