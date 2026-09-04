import Foundation
import SwiftData

/// Categoria de um resultado de busca — também define o rótulo do grupo e o
/// ícone padrão usados na tela de busca.
enum SearchCategory: Int, CaseIterable {
    case collection, notebook, section, page, audio

    var label: String {
        switch self {
        case .collection: return "Coleções"
        case .notebook: return "Cadernos"
        case .section: return "Seções"
        case .page: return "Páginas"
        case .audio: return "Ideias faladas"
        }
    }

    var icon: String {
        switch self {
        case .collection: return "folder.fill"
        case .notebook: return "book.closed.fill"
        case .section: return "tag.fill"
        case .page: return "doc.text.fill"
        case .audio: return "waveform"
        }
    }
}

/// Um resultado de busca — pode ter vindo do NOME (coleção/caderno/seção,
/// sempre visíveis mesmo quando o conteúdo é protegido, do mesmo jeito que a
/// tela inicial já mostra capas de cadernos trancados) ou do CONTEÚDO (texto
/// reconhecido de uma página escrita, ou transcrição de uma ideia falada).
struct SearchResult: Identifiable {
    enum Target {
        case collection(NotebookGroup)
        case notebook(Notebook)
        case section(Section)
        case page(NotebookPage)
        case audioMemo(AudioMemo)
    }

    let id: String
    let category: SearchCategory
    let target: Target
    let title: String
    let subtitle: String
    let snippet: String?
    let tintColor: NotebookColor
}

/// Busca central do app — junta nomes (coleção/caderno/seção) e conteúdo
/// (OCR das páginas + transcrição dos áudios) num resultado só. Fica isolada
/// aqui de propósito: seja qual for a forma de expor isso no futuro (uma
/// tela, uma API, um MCP), é só reaproveitar `search(term:modelContext:)`
/// sem duplicar a lógica de filtro/permissão em outro lugar.
enum SearchIndex {
    @MainActor
    static func search(term: String, modelContext: ModelContext) -> [SearchResult] {
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }

        var results: [SearchResult] = []

        let collections = (try? modelContext.fetch(FetchDescriptor<NotebookGroup>())) ?? []
        for collection in collections where collection.title.localizedStandardContains(query) {
            results.append(SearchResult(
                id: "collection-\(collection.id)",
                category: .collection,
                target: .collection(collection),
                title: collection.title,
                subtitle: "\(collection.notebooks.count) \(collection.notebooks.count == 1 ? "caderno" : "cadernos")",
                snippet: nil,
                tintColor: collection.color
            ))
        }

        let notebooks = (try? modelContext.fetch(FetchDescriptor<Notebook>())) ?? []
        for notebook in notebooks where notebook.title.localizedStandardContains(query) {
            results.append(SearchResult(
                id: "notebook-\(notebook.id)",
                category: .notebook,
                target: .notebook(notebook),
                title: notebook.title,
                subtitle: notebook.group?.title ?? "Sem coleção",
                snippet: nil,
                tintColor: notebook.coverColor
            ))
        }

        // Seções e páginas de cadernos protegidos ficam de fora — o título
        // do caderno em si aparece (já é visível na tela inicial sem
        // autenticar), mas o conteúdo de dentro, não.
        let sections = (try? modelContext.fetch(FetchDescriptor<Section>())) ?? []
        for section in sections where !isProtected(section.notebook) && section.title.localizedStandardContains(query) {
            let notebookTitle = section.notebook?.title ?? "Caderno"
            results.append(SearchResult(
                id: "section-\(section.id)",
                category: .section,
                target: .section(section),
                title: section.title,
                subtitle: notebookTitle,
                snippet: nil,
                tintColor: section.tabColor
            ))
        }

        let pages = (try? modelContext.fetch(FetchDescriptor<NotebookPage>())) ?? []
        for page in pages
        where !page.recognizedText.isEmpty
            && !isProtected(page.section?.notebook)
            && page.recognizedText.localizedStandardContains(query) {
            let section = page.section
            let notebookTitle = section?.notebook?.title ?? "Caderno"
            let pageNumber = (section?.sortedPages.firstIndex(where: { $0.id == page.id }) ?? 0) + 1
            results.append(SearchResult(
                id: "page-\(page.id)",
                category: .page,
                target: .page(page),
                title: notebookTitle,
                subtitle: "\(section?.title ?? "Seção") · pág. \(pageNumber)",
                snippet: snippet(for: page.recognizedText, around: query),
                tintColor: section?.tabColor ?? .blue
            ))
        }

        let memos = (try? modelContext.fetch(FetchDescriptor<AudioMemo>())) ?? []
        for memo in memos where !memo.isProtected {
            let matchesTitle = memo.title.localizedStandardContains(query)
            let transcript = memo.transcript ?? ""
            let matchesTranscript = !transcript.isEmpty && transcript.localizedStandardContains(query)
            guard matchesTitle || matchesTranscript else { continue }
            results.append(SearchResult(
                id: "audio-\(memo.id)",
                category: .audio,
                target: .audioMemo(memo),
                title: memo.title,
                subtitle: memo.section?.notebook?.title ?? "Sem caderno",
                snippet: matchesTranscript ? snippet(for: transcript, around: query) : nil,
                tintColor: memo.coverColor
            ))
        }

        return results
    }

    /// Páginas favoritadas, mais recente primeiro — mostradas na busca ANTES
    /// de digitar qualquer coisa, já que favoritar só valia a pena se desse
    /// pra achar essas páginas rápido sem lembrar em qual caderno estão.
    @MainActor
    static func favoritePages(modelContext: ModelContext) -> [SearchResult] {
        let pages = (try? modelContext.fetch(FetchDescriptor<NotebookPage>())) ?? []
        return pages
            .filter { $0.isFavorite && !isProtected($0.section?.notebook) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { page in
                let section = page.section
                let notebookTitle = section?.notebook?.title ?? "Caderno"
                let pageNumber = (section?.sortedPages.firstIndex(where: { $0.id == page.id }) ?? 0) + 1
                return SearchResult(
                    id: "favorite-page-\(page.id)",
                    category: .page,
                    target: .page(page),
                    title: notebookTitle,
                    subtitle: "\(section?.title ?? "Seção") · pág. \(pageNumber)",
                    snippet: page.recognizedText.isEmpty ? nil : String(page.recognizedText.prefix(90)),
                    tintColor: section?.tabColor ?? .blue
                )
            }
    }

    private static func isProtected(_ notebook: Notebook?) -> Bool {
        guard let notebook else { return false }
        return notebook.isLocked || (notebook.group?.isLocked ?? false)
    }

    /// Recorta um pedaço do texto ao redor da primeira ocorrência do termo,
    /// pra mostrar contexto no resultado (tipo "…ontem fui pensando que…").
    private static func snippet(for text: String, around query: String, radius: Int = 44) -> String {
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(text.prefix(90))
        }
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var result = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if start != text.startIndex { result = "…" + result }
        if end != text.endIndex { result += "…" }
        return result
    }
}
