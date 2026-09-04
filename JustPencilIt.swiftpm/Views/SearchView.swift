import SwiftUI
import SwiftData

/// A "busca poderosa": olha ao mesmo tempo pros nomes (coleções, cadernos,
/// seções) e pro conteúdo (texto reconhecido nas páginas escritas e
/// transcrição das ideias faladas) — pensada pra quem tem muitos cadernos,
/// alguns bem antigos, e não lembra exatamente onde guardou algo.
/// Tela cheia, com um fundo ilustrado leve (lupas, tags, ondas sonoras) no
/// mesmo espírito das outras telas do app.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var onSelectCollection: (NotebookGroup) -> Void = { _ in }
    var onSelectNotebook: (Notebook) -> Void = { _ in }
    var onSelectSection: (Section) -> Void = { _ in }
    var onSelectPage: (NotebookPage) -> Void = { _ in }
    var onSelectAudioMemo: (AudioMemo) -> Void = { _ in }

    @State private var query = ""
    @State private var results: [SearchResult] = []
    // Páginas favoritadas — mostradas antes de digitar qualquer coisa, como
    // um atalho rápido pras páginas de referência marcadas em qualquer
    // caderno, sem precisar lembrar (ou digitar) onde elas estão.
    @State private var favoritePages: [SearchResult] = []
    @FocusState private var isFieldFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var groupedResults: [ResultGroup] {
        SearchCategory.allCases.compactMap { category in
            let items = results.filter { $0.category == category }
            return items.isEmpty ? nil : ResultGroup(category: category, items: items)
        }
    }

    var body: some View {
        ZStack {
            SearchBackgroundView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                searchField

                if trimmedQuery.count < 2 {
                    if favoritePages.isEmpty {
                        emptyHint
                        Spacer()
                    } else {
                        favoritesList
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 40)
                    Spacer()
                } else {
                    resultsList
                }
            }
        }
        .onAppear {
            isFieldFocused = true
            favoritePages = SearchIndex.favoritePages(modelContext: modelContext)
        }
        .onChange(of: query) { _, newValue in
            results = SearchIndex.search(term: newValue, modelContext: modelContext)
        }
    }

    /// Lista de páginas favoritas mostrada antes de digitar qualquer termo
    /// — mesmo visual dos resultados de busca normais, só que reunidos numa
    /// única seção com estrela em vez de agrupados por categoria.
    private var favoritesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.caption.weight(.bold))
                    Text("Páginas favoritas")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.4)
                    Text("\(favoritePages.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow, in: Capsule())
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

                ForEach(favoritePages) { result in
                    SearchResultRow(result: result, query: "") {
                        select(result)
                    }
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle().strokeBorder(Color.black, lineWidth: 2.5)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 0) {
                Text("Busca")
                    .font(.system(.title, design: .rounded).weight(.heavy))
                if trimmedQuery.count >= 2 {
                    Text("\(results.count) \(results.count == 1 ? "resultado" : "resultados")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .accessibilityLabel("Fechar")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Nomes, páginas escritas, ideias faladas…", text: $query)
                .focused($isFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var emptyHint: some View {
        ContentUnavailableView(
            "Busque em tudo",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Nomes de coleções, cadernos e seções — e o conteúdo escrito ou falado dentro deles.")
        )
        .padding(.top, 40)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(groupedResults) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        CategoryHeader(category: group.category, count: group.items.count)
                        ForEach(group.items) { result in
                            SearchResultRow(result: result, query: trimmedQuery) {
                                select(result)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func select(_ result: SearchResult) {
        switch result.target {
        case .collection(let collection):
            onSelectCollection(collection)
        case .notebook(let notebook):
            onSelectNotebook(notebook)
        case .section(let section):
            onSelectSection(section)
        case .page(let page):
            onSelectPage(page)
        case .audioMemo(let memo):
            onSelectAudioMemo(memo)
        }
    }
}

/// Um grupo de resultados da mesma categoria (ex: todas as "Páginas"
/// achadas), pronto pra virar uma seção na lista de resultados.
private struct ResultGroup: Identifiable {
    var category: SearchCategory
    var items: [SearchResult]
    var id: Int { category.rawValue }
}

private struct CategoryHeader: View {
    var category: SearchCategory
    var count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category.icon)
                .font(.caption.weight(.bold))
            Text(category.label)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.4)
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor, in: Capsule())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

private struct SearchResultRow: View {
    var result: SearchResult
    var query: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(result.tintColor.color.gradient)
                    Image(systemName: result.category.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(result.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let snippet = result.snippet {
                        Text(highlighted(snippet, query: query))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    /// Realça a ocorrência do termo buscado dentro do trecho de contexto.
    private func highlighted(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        if !query.isEmpty, let range = attributed.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].font = .footnote.weight(.bold)
            attributed[range].foregroundColor = .accentColor
        }
        return attributed
    }
}

/// Fundo leve e discreto (fica atrás de cards de resultado, não pode
/// competir com eles): ícones flutuantes ligados à ideia de buscar —
/// lupas, tags, cadernos, ondas sonoras.
private struct SearchBackgroundView: View {
    private struct Item {
        let symbol: String
        let size: CGFloat
        let baseX: CGFloat
        let baseY: CGFloat
        let speed: Double
        let phase: Double
        let amplitude: CGFloat
        let color: Color
    }

    private let items: [Item] = [
        Item(symbol: "magnifyingglass", size: 42, baseX: 0.08, baseY: 0.1, speed: 0.3, phase: 0.2, amplitude: 14, color: .blue),
        Item(symbol: "book.closed.fill", size: 32, baseX: 0.86, baseY: 0.08, speed: 0.26, phase: 1.4, amplitude: 13, color: .orange),
        Item(symbol: "tag.fill", size: 26, baseX: 0.3, baseY: 0.34, speed: 0.4, phase: 2.1, amplitude: 12, color: .green),
        Item(symbol: "folder.fill", size: 34, baseX: 0.72, baseY: 0.38, speed: 0.24, phase: 0.7, amplitude: 15, color: .purple),
        Item(symbol: "waveform", size: 28, baseX: 0.12, baseY: 0.64, speed: 0.32, phase: 2.9, amplitude: 12, color: .pink),
        Item(symbol: "sparkles", size: 24, baseX: 0.9, baseY: 0.58, speed: 0.36, phase: 1.0, amplitude: 11, color: .yellow),
        Item(symbol: "doc.text.fill", size: 28, baseX: 0.46, baseY: 0.18, speed: 0.38, phase: 1.8, amplitude: 12, color: .teal),
        Item(symbol: "text.magnifyingglass", size: 30, baseX: 0.6, baseY: 0.84, speed: 0.27, phase: 0.4, amplitude: 14, color: .indigo),
        Item(symbol: "quote.bubble.fill", size: 26, baseX: 0.05, baseY: 0.4, speed: 0.35, phase: 2.5, amplitude: 11, color: .mint),
        Item(symbol: "bookmark.fill", size: 24, baseX: 0.36, baseY: 0.58, speed: 0.22, phase: 1.2, amplitude: 13, color: .cyan)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.systemGroupedBackground)

                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        let x = item.baseX * geometry.size.width + CGFloat(cos(t * item.speed + item.phase)) * item.amplitude
                        let y = item.baseY * geometry.size.height + CGFloat(sin(t * item.speed + item.phase)) * item.amplitude
                        let rotation = sin(t * item.speed + item.phase) * 8

                        Image(systemName: item.symbol)
                            .font(.system(size: item.size, weight: .semibold))
                            .foregroundStyle(item.color.opacity(0.14))
                            .rotationEffect(.degrees(rotation))
                            .position(x: x, y: y)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
