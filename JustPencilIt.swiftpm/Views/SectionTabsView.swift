import SwiftUI

/// Barra de abas com as seções do caderno (ex: "Física", "Matemática"),
/// tipo as divisórias de um caderno físico. Toque longo numa aba pra
/// renomear ou excluir; "+" no final pra criar uma nova. Também é onde uma
/// página arrastada da grade (ver PageGridView) pode ser solta pra mudar
/// de seção — cada aba vira um alvo de drop.
struct SectionTabsView: View {
    @Bindable var notebook: Notebook
    @Binding var selectedSectionID: UUID?
    var onRename: (Section) -> Void
    var onDelete: (Section) -> Void
    var onDropPages: (Section, [String]) -> Void = { _, _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(notebook.sortedSections) { section in
                    let isSelected = section.id == selectedSectionID
                    SectionTabButton(
                        section: section,
                        isSelected: isSelected,
                        onSelect: { selectedSectionID = section.id },
                        onDropPages: { ids in onDropPages(section, ids) }
                    )
                    .contextMenu {
                        Button {
                            onRename(section)
                        } label: {
                            Label("Renomear", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            onDelete(section)
                        } label: {
                            Label("Excluir seção", systemImage: "trash")
                        }
                    }
                }

                Button(action: addSection) {
                    Image(systemName: "plus")
                        .padding(10)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func addSection() {
        let section = Section(title: "Seção \(notebook.sections.count + 1)", order: notebook.sections.count)
        section.notebook = notebook
        notebook.sections.append(section)
        let firstPage = NotebookPage(order: 0)
        firstPage.section = section
        section.pages.append(firstPage)
        selectedSectionID = section.id
    }
}

/// Uma aba de seção — separada do resto pra poder ter seu próprio estado de
/// "uma página está sendo arrastada por cima" (`isTargeted`), que destaca a
/// aba enquanto isso acontece.
private struct SectionTabButton: View {
    var section: Section
    var isSelected: Bool
    var onSelect: () -> Void
    var onDropPages: ([String]) -> Void

    @State private var isTargeted = false

    var body: some View {
        Button(action: onSelect) {
            // Mesma fonte "Noteworthy" usada no nome do caderno
            // (ver NotebookCoverView.titleFontName).
            Text(section.title)
                .font(.custom(NotebookCoverView.titleFontName, size: 17))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        isSelected
                            ? section.tabColor.color
                            : section.tabColor.color.opacity(isTargeted ? 0.4 : 0.16)
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        isTargeted ? section.tabColor.color : section.tabColor.color.opacity(isSelected ? 0 : 0.4),
                        lineWidth: isTargeted ? 2.5 : 1
                    )
                )
                .foregroundStyle(
                    isSelected ? Color.white : section.tabColor.color
                )
                .scaleEffect(isTargeted ? 1.08 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTargeted)
        }
        .dropDestination(for: PageDragPayload.self) { payloads, _ in
            let ids = payloads.flatMap { $0.pageIDs }
            guard !ids.isEmpty else { return false }
            onDropPages(ids)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}
