import SwiftUI
import SwiftData

@main
struct JustPencilItApp: App {
    var body: some Scene {
        WindowGroup {
            NotebookListView()
                // Sincroniza com a Caderneta (Android) enquanto o app está aberto.
                .modifier(RelaySyncDriver())
        }
        .modelContainer(for: [Notebook.self, NotebookGroup.self, Section.self, NotebookPage.self, AudioMemo.self])
    }
}
