import Foundation
import BackgroundTasks
import SwiftData

/// Sincronização com a Caderneta com o app fechado, pelo `BGAppRefreshTask`.
///
/// Quem decide quando roda é o iOS (conforme o uso do app, bateria e rede):
/// pode ser a cada poucas horas, ou nunca se o app quase não é aberto. Por
/// isso é um extra — a sincronização de verdade continua sendo a do app
/// aberto, a cada minuto (`RelaySyncDriver`).
///
/// Em segundo plano o iPad só **importa** as fitas e publica o snapshot. A
/// transcrição fica para quando o app abrir: o iOS pode suspender a tarefa a
/// qualquer momento, e uma transcrição cortada no meio viraria "falhou".
@MainActor
enum RelayBackgroundSync {
    /// Também listado em `BGTaskSchedulerPermittedIdentifiers` (Support/Info-Additions.plist).
    static let identifier = "com.tatarana.justpencilit.sync"

    static func schedule() {
        guard RelaySync.shared.isPaired else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        // Não antes de 15 min; o iOS costuma escolher bem mais tarde.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func run(container: ModelContainer) async {
        // Cada tarefa agenda a próxima: o iOS não repete sozinho.
        schedule()
        await RelaySync.shared.syncNow(modelContext: container.mainContext, inBackground: true)
    }
}
