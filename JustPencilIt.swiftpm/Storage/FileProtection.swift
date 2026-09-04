import Foundation
import SwiftData

/// Camada de segurança dos dados em repouso: usa a Data Protection nativa
/// do iOS (o mesmo mecanismo que apps de banco/saúde usam) em vez de
/// qualquer criptografia própria — a chave de cada arquivo protegido fica
/// atrelada à senha do aparelho + Secure Enclave, sem gerenciamento de
/// chave nenhum da nossa parte, e sem custo de performance perceptível.
///
/// Usamos `.completeUnlessOpen` em 100% dos casos, de propósito, pra manter
/// simples: é a classe que a própria Apple recomenda pra bancos de dados e
/// arquivos que o app pode precisar gravar com a tela apagada (ex: um
/// traço salvo, ou o OCR rodando em segundo plano) — o conteúdo fica
/// protegido em repouso sem quebrar essas gravações, ao contrário de
/// `.complete`, que tornaria os arquivos ilegíveis enquanto o iPad está
/// bloqueado.
enum FileProtection {
    static let level: FileProtectionType = .completeUnlessOpen

    /// As mesmas opções, prontas pra passar direto num `Data.write(to:options:)`
    /// — mais simples que escrever e depois reaplicar a proteção.
    static let writingOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUnlessOpen]

    /// Aplica a proteção a um arquivo já existente em disco — usado quando
    /// quem escreveu o arquivo não foi um `Data.write` nosso (ex: o
    /// `AVAudioRecorder` grava sozinho, o `UIGraphicsPDFRenderer` também).
    /// Silencioso em caso de erro: nunca deve travar um fluxo de
    /// salvar/exportar por causa disso.
    static func apply(to url: URL) {
        try? FileManager.default.setAttributes([.protectionKey: level], ofItemAtPath: url.path)
    }

    /// O banco do SwiftData é SQLite por baixo dos panos — além do arquivo
    /// principal, existem os auxiliares `-wal`/`-shm` (onde ficam mudanças
    /// ainda não gravadas no arquivo principal). Sem proteger os três,
    /// dados recentes ficariam desprotegidos mesmo com o arquivo principal
    /// coberto.
    static func applyToSQLiteStore(at url: URL) {
        apply(to: url)
        apply(to: URL(fileURLWithPath: url.path + "-wal"))
        apply(to: URL(fileURLWithPath: url.path + "-shm"))
    }

    /// Roda a cada abertura do app: garante que o arquivo do banco do
    /// SwiftData esteja protegido. Não existe um jeito de passar essa opção
    /// na criação do `ModelContainer`, então isso substitui esse passo —
    /// idempotente e barato (só três `setAttributes`, sem enumerar nada).
    ///
    /// Não faz uma varredura geral de desenhos/áudios: cada arquivo novo já
    /// nasce protegido no momento em que é escrito (ver `writingOptions` e
    /// os usos de `apply(to:)` no `AudioRecorderService`/`PDFExportService`)
    /// — uma varredura só faria sentido pra cobrir arquivos gravados ANTES
    /// dessa proteção existir no app, e isso não existe: ninguém além de
    /// quem está testando agora tem dados salvos.
    static func protectDatabase(modelContext: ModelContext) {
        guard let storeURL = modelContext.container.configurations.first?.url else { return }
        applyToSQLiteStore(at: storeURL)
    }

    /// Lê de volta, direto do sistema de arquivos, a classe de proteção
    /// REALMENTE aplicada a um arquivo agora — não é o que a gente PEDIU
    /// pra aplicar, é o que o iOS confirma que está valendo. Usado pela
    /// tela de Ajustes pra dar uma resposta concreta a "isso tá mesmo
    /// criptografado?", sem precisar de Xcode/Console.
    static func currentProtection(of url: URL) -> FileProtectionType? {
        guard let value = try? FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType else {
            return nil
        }
        return value
    }
}
