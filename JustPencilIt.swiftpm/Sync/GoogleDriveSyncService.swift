import Foundation

/// Ponto de integração para sincronizar cadernos com o Google Drive.
/// Implementação real deve usar o Google Sign-In SDK + Google Drive API
/// (via GoogleAPIClientForREST ou chamadas REST diretas com OAuth2).
protocol NotebookSyncService {
    func upload(notebook: Notebook, pages: [NotebookPage]) async throws
    func download(notebookID: UUID) async throws -> (Notebook, [NotebookPage])
    func listRemoteNotebooks() async throws -> [Notebook]
}

/// Stub inicial — substituir pela integração real com Google Drive.
final class GoogleDriveSyncService: NotebookSyncService {
    func upload(notebook: Notebook, pages: [NotebookPage]) async throws {
        // TODO: autenticar via Google Sign-In e enviar arquivos para o Drive
    }

    func download(notebookID: UUID) async throws -> (Notebook, [NotebookPage]) {
        // TODO: baixar caderno e páginas do Drive
        throw NSError(domain: "GoogleDriveSyncService", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Não implementado ainda"
        ])
    }

    func listRemoteNotebooks() async throws -> [Notebook] {
        // TODO: listar cadernos salvos no Drive
        return []
    }
}
