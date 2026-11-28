import SwiftUI
import SwiftData

@main
struct JustPencilItApp: App {
    /// O mesmo banco que o `.modelContainer(for:)` criava (configuração
    /// padrão, mesmo arquivo), agora guardado aqui para a sincronização em
    /// segundo plano também conseguir usar, sem nenhuma tela aberta.
    let container: ModelContainer = {
        do {
            return try ModelContainer(for: Notebook.self, NotebookGroup.self, Section.self, NotebookPage.self, AudioMemo.self)
        } catch {
            fatalError("Não deu pra abrir o banco de dados: \(error)")
        }
    }()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NotebookListView()
                // Sincroniza com a Caderneta (Android) enquanto o app está aberto.
                .modifier(RelaySyncDriver())
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Saiu da tela: pede ao iOS uma rodada em segundo plano mais tarde.
            if phase == .background { RelayBackgroundSync.schedule() }
        }
        .backgroundTask(.appRefresh(RelayBackgroundSync.identifier)) {
            await RelayBackgroundSync.run(container: container)
        }
    }
}
