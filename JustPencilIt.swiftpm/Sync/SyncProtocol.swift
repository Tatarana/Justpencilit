import Foundation

/// Formato dos pacotes trocados com a Caderneta (Android). Espelha
/// `SyncProtocol.kt` de lá; a descrição completa está em
/// docs/SYNC_PROTOCOL.md do repo justpencilit-android. Mudou aqui, muda lá.
///
/// Datas em milissegundos desde 1970 (UTC). Ids são UUIDs em maiúsculas
/// (`uuidString`). Cores e status usam os valores crus daqui.
enum SyncProtocol {
    static let version = 0
    static let kindAudioMemo = "audio_memo"
}

/// Celular → iPad. No relay, cada pacote traz uma fita só em `items`.
struct InboxManifest: Codable {
    let protocolVersion: Int
    let deviceId: String
    let deviceName: String
    let sentAt: Int64
    let items: [InboxItemDTO]
}

struct InboxItemDTO: Codable {
    let kind: String
    let id: String
    /// true = fita nova (o áudio vem junto); false = só título/etiqueta mudaram.
    let isNew: Bool
    let title: String
    let createdAt: Int64
    let updatedAt: Int64
    let durationMs: Int64
    let audioFileName: String?
    let coverColor: String
    let sectionId: String?
}

/// iPad → celular: cópia de leitura + o que o iPad processou.
struct SnapshotDTO: Codable {
    let protocolVersion: Int
    let generatedAt: Int64
    /// Só seções de cadernos NÃO protegidos.
    let sections: [SectionDTO]
    /// Todas as fitas que vieram do celular e ainda existem aqui.
    let memoUpdates: [MemoUpdateDTO]
}

struct SectionDTO: Codable, Hashable {
    let id: String
    let notebookId: String
    let notebookTitle: String
    let title: String
    let order: Int
    let notebookColor: String
}

struct MemoUpdateDTO: Codable, Hashable {
    let id: String
    let title: String?
    let transcript: String?
    let transcriptionStatus: String
}

extension Date {
    var millisecondsSince1970: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }

    init(millisecondsSince1970 ms: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }
}
