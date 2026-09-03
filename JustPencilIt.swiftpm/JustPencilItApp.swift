import SwiftUI
import SwiftData

@main
struct JustPencilItApp: App {
    var body: some Scene {
        WindowGroup {
            NotebookListView()
        }
        .modelContainer(for: [Notebook.self, NotebookGroup.self, Section.self, NotebookPage.self, AudioMemo.self])
    }
}
