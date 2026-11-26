import Foundation
import SwiftData

/// Status da transcrição de um memo de áudio. Guardado como String (não o
/// enum direto) porque o SwiftData lida melhor com migração de valores
/// simples do que com enums associados a case futuros — String também é
/// mais barato de migrar se um dia a gente adicionar um novo status.
enum TranscriptionStatus: String, Codable {
    case pending      // ainda não tentou transcrever
    case transcribing // rodando agora
    case done         // texto pronto (ver `transcript`)
    case failed       // tentou e não deu — usuário pode tentar de novo
}

/// Um memo de voz — "ideia rápida" gravada, guardada numa biblioteca central
/// (a "fitoteca") em vez de presa a uma página específica. Pode opcionalmente
/// ganhar uma etiqueta pra uma seção de caderno (`section`), sem que isso
/// mova o arquivo: é só uma referência, pra aparecer também dentro daquele
/// caderno se o usuário quiser.
@Model
final class AudioMemo: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    // Em segundos — calculada uma vez ao parar de gravar, evita reabrir o
    // arquivo de áudio só pra saber a duração toda vez que a fitoteca renderiza.
    var duration: TimeInterval
    var audioFileName: String
    var transcript: String?
    var transcriptionStatusRaw: String = TranscriptionStatus.pending.rawValue
    // Cor do "corpo" da fita cassete na fitoteca — mesma paleta dos cadernos,
    // escolhida automaticamente pela ordem de criação.
    var coverColor: NotebookColor = NotebookColor.blue
    // Etiqueta opcional pra uma seção de caderno — não afeta onde o arquivo
    // fica salvo, só faz o memo aparecer também dentro daquele caderno.
    var section: Section?

    init(title: String, coverColor: NotebookColor, audioFileName: String) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.duration = 0
        self.audioFileName = audioFileName
        self.coverColor = coverColor
    }

    var transcriptionStatus: TranscriptionStatus {
        get { TranscriptionStatus(rawValue: transcriptionStatusRaw) ?? .pending }
        set { transcriptionStatusRaw = newValue.rawValue }
    }

    /// Protegido se a seção associada pertencer a um caderno ou coleção
    /// protegidos — mesma regra usada pelas capas de caderno.
    var isProtected: Bool {
        guard let notebook = section?.notebook else { return false }
        return notebook.isLocked || (notebook.group?.isLocked ?? false)
    }
}
