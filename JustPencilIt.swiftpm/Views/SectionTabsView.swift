import SwiftUI

/// Barra de abas com as seções do caderno (ex: "Física", "Matemática"),
/// tipo as divisórias de um caderno físico. Toque longo numa aba pra
/// renomear ou excluir; "+" no final pra criar uma nova.
struct SectionTabsView: View {
    @Bindable var notebook: Notebook
    @Binding var selectedSectionID: UUID?
    var onRename: (Section) -> Void
    var onDelete: (Section) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(notebook.sortedSections) { section in
                    let isSelected = section.id == selectedSectionID
                    Button {
                        selectedSectionID = section.id
                    } label: {
                        Text(section.title)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    isSelected
                                        ? section.tabColor.color
                                        : section.tabColor.color.opacity(0.16)
                                )
                            )
                            .overlay(
                                Capsule().strokeBorder(section.tabColor.color.opacity(isSelected ? 0 : 0.4), lineWidth: 1)
                            )
                            .foregroundStyle(
                                isSelected ? Color.white : section.tabColor.color
                            )
                    }
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
