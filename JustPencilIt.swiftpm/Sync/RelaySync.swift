import Foundation
import SwiftUI
import SwiftData
import CryptoKit
import Observation

enum SyncSetupError: Error, LocalizedError {
    case cryptoSelfTestFailed
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .cryptoSelfTestFailed:
            return "A verificação da criptografia falhou neste iPad. O pareamento foi cancelado para não gerar dados que o celular não consiga abrir."
        case .invalidURL:
            return "Endereço do servidor inválido. Ele precisa começar com https://"
        }
    }
}

/// Sincronização com a Caderneta (Android) pelo relay na Cloudflare.
///
/// O iPad continua sendo a central: para cada celular pareado, ele
/// **importa** o que o celular deixou na caixa de entrada (`inbox/`: fitas
/// novas, edições e exclusões), transcreve, e **publica** uma cópia de
/// leitura (`snapshot/manifest`) com as seções, as transcrições e as fitas
/// apagadas aqui. Tudo sobe e desce cifrado (`RelayCrypto`); o servidor não
/// lê nada.
///
/// Protocolo: docs/SYNC_PROTOCOL.md no repo justpencilit-android e
/// docs/PROTOCOL.md no repo justpencilit-relay.
@MainActor
@Observable
final class RelaySync {
    static let shared = RelaySync()

    enum Status: Equatable {
        case idle
        case running
        /// Sem internet ou servidor fora do ar: nada de errado, tenta depois.
        case offline
        case done(at: Date, imported: Int)
        case failed(String)
    }

    private(set) var pairings: [RelayPairing] = PairingStore.load()
    /// Como terminou a última rodada de cada celular, pela caixa.
    private(set) var statusByMailbox: [String: Status] = [:]
    private(set) var isRunning = false

    var isPaired: Bool { !pairings.isEmpty }

    func status(of pairing: RelayPairing) -> Status {
        isRunning ? .running : (statusByMailbox[pairing.mailboxID] ?? .idle)
    }

    private static let snapshotKey = "snapshot/manifest"
    private static let deviceInfoKey = "device/info"
    /// Fitas apagadas aqui são avisadas ao celular por este tempo. Um celular
    /// parado mais que isso pode ficar com uma cópia velha — ele mesmo apaga.
    private static let tombstoneLifetime: TimeInterval = 90 * 24 * 60 * 60

    // MARK: - Pareamento

    /// Cria uma caixa nova no relay para mais um celular e devolve o código do QR.
    func pair(relayURL raw: String) async throws -> RelayPairingCode {
        guard RelayCrypto.selfTest() else { throw SyncSetupError.cryptoSelfTestFailed }

        var address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while address.hasSuffix("/") { address.removeLast() }
        guard let url = URL(string: address), url.scheme == "https", url.host != nil else {
            throw SyncSetupError.invalidURL
        }

        let code = RelayPairingCode.generate(relayURL: address, peerName: PairingStore.ownName)
        let newPairing = RelayPairing(
            relayURL: address,
            mailboxID: code.mailboxID,
            masterKey: code.masterKey,
            pairedAt: Date()
        )
        guard let client = newPairing.client else { throw SyncSetupError.invalidURL }
        try await client.register()

        var updated = pairings
        updated.append(newPairing)
        try PairingStore.save(updated)
        pairings = updated
        return code
    }

    /// Apaga a caixa desse celular no relay e esquece ele. Devolve `false` se
    /// não deu pra apagar no servidor (sem internet) — o pareamento local some
    /// mesmo assim, e a caixa órfã fica inacessível sem a chave (e o relay
    /// apaga caixas paradas há 180 dias).
    func unpair(_ pairing: RelayPairing) async -> Bool {
        var deletedOnServer = true
        do {
            try await pairing.client?.deleteMailbox()
        } catch {
            deletedOnServer = false
        }
        let remaining = pairings.filter { $0.mailboxID != pairing.mailboxID }
        try? PairingStore.save(remaining)
        pairings = remaining
        statusByMailbox[pairing.mailboxID] = nil
        UserDefaults.standard.removeObject(forKey: Self.snapshotHashKey(pairing.mailboxID))
        if let deviceID = pairing.deviceID { Tombstones.clear(deviceID: deviceID) }
        return deletedOnServer
    }

    // MARK: - Sincronização

    /// Uma rodada com cada celular: importa a caixa de entrada e publica o
    /// snapshot se mudou. Barato quando não há nada novo (uma listagem e
    /// nenhum envio por celular).
    ///
    /// [inBackground]: rodada do `BGAppRefreshTask` — importa, mas deixa a
    /// transcrição para quando o app abrir (ver `RelayBackgroundSync`).
    func syncNow(modelContext: ModelContext, inBackground: Bool = false) async {
        guard !isRunning, !pairings.isEmpty else { return }
        isRunning = true
        defer { isRunning = false }

        for pairing in pairings {
            statusByMailbox[pairing.mailboxID] = await syncOne(pairing, modelContext: modelContext, transcribe: !inBackground)
        }
        if !inBackground { resumeTranscriptions(modelContext: modelContext) }
    }

    /// Fitas do celular que ficaram sem transcrição: chegaram em segundo plano
    /// (ficam "pendentes") ou o app foi fechado no meio (ficam "transcrevendo"
    /// sem ninguém transcrevendo de fato).
    private func resumeTranscriptions(modelContext: ModelContext) {
        guard let memos = try? modelContext.fetch(FetchDescriptor<AudioMemo>()) else { return }
        for memo in memos where memo.originDeviceID != nil {
            let stuck = memo.transcriptionStatus == .pending
                || (memo.transcriptionStatus == .transcribing && !MemoTranscription.isRunning(memo.id))
            if stuck { MemoTranscription.start(memo, in: modelContext) }
        }
    }

    /// Republica o snapshot de todos os celulares sem mexer no status — usado
    /// quando uma transcrição termina ou uma fita é apagada aqui.
    func publishSnapshots(modelContext: ModelContext) async {
        for pairing in pairings {
            guard let client = pairing.client else { continue }
            try? await publishSnapshot(for: pairing, client: client, modelContext: modelContext)
        }
    }

    /// Chamado ANTES de apagar um memo aqui: se ele veio de um celular, o
    /// celular fica sabendo pelo próximo snapshot e apaga a cópia dele.
    func recordDeletion(of memo: AudioMemo) {
        guard let deviceID = memo.originDeviceID else { return }
        Tombstones.add(memoID: memo.id.uuidString, deviceID: deviceID)
    }

    private func syncOne(_ pairing: RelayPairing, modelContext: ModelContext, transcribe: Bool) async -> Status {
        guard let client = pairing.client else { return .failed("Endereço do servidor inválido.") }
        do {
            var current = pairing
            try await learnDevice(&current, client: client)
            let result = try await importInbox(&current, client: client, modelContext: modelContext, transcribe: transcribe)
            saveIfChanged(current, original: pairing)
            if let newerVersion = result.newerVersionSeen {
                return .failed("A Caderneta deste celular está numa versão mais nova (protocolo \(newerVersion)). Atualize o JustPencilIt.")
            }
            try await publishSnapshot(for: current, client: client, modelContext: modelContext)
            return .done(at: Date(), imported: result.imported)
        } catch let error as RelayError {
            switch error {
            case .unreachable:
                return .offline
            case .http(let status, _) where status == 429:
                // Limite de pedidos do relay: só espera a próxima rodada.
                return .offline
            case .http:
                return .failed(error.isPairingRevoked
                    ? "O pareamento não vale mais no servidor. Desfaça e pareie o celular de novo."
                    : (error.errorDescription ?? "Erro no servidor."))
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// O celular se apresenta em `device/info` logo depois de parear: assim o
    /// iPad sabe o nome e o id dele antes mesmo da primeira fita.
    private func learnDevice(_ pairing: inout RelayPairing, client: RelayClient) async throws {
        guard pairing.deviceID == nil,
              let blob = try await client.get(Self.deviceInfoKey),
              let plain = try? RelayCrypto.open(blob, key: pairing.keys.encKey, objectKey: Self.deviceInfoKey),
              let info = try? JSONDecoder().decode(DeviceInfoDTO.self, from: plain)
        else { return }
        pairing.deviceID = info.deviceId
        pairing.phoneName = info.deviceName
    }

    private func saveIfChanged(_ pairing: RelayPairing, original: RelayPairing) {
        guard pairing.deviceID != original.deviceID || pairing.phoneName != original.phoneName,
              let index = pairings.firstIndex(where: { $0.mailboxID == pairing.mailboxID })
        else { return }
        var updated = pairings
        updated[index] = pairing
        if (try? PairingStore.save(updated)) != nil { pairings = updated }
    }

    // MARK: Caixa de entrada (celular → iPad)

    private struct ImportResult {
        var imported = 0
        var newerVersionSeen: Int?
    }

    private func importInbox(_ pairing: inout RelayPairing, client: RelayClient, modelContext: ModelContext, transcribe: Bool) async throws -> ImportResult {
        let key = pairing.keys.encKey
        let objects = try await client.list(prefix: "inbox/")
        let existingKeys = Set(objects.map(\.key))
        // Em ordem de edição: a fita nova chega antes das renomeações dela.
        let entries = objects.compactMap { InboxEntry(key: $0.key) }.sorted { $0.updatedAt < $1.updatedAt }

        var result = ImportResult()
        var newMemos: [AudioMemo] = []
        // Fitas cujo áudio ainda não chegou: as edições seguintes delas
        // esperam também, para não serem aplicadas antes da fita existir.
        var blockedMemoIDs: Set<String> = []

        for entry in entries {
            if blockedMemoIDs.contains(entry.memoID) { continue }
            guard let blob = try await client.get(entry.key) else { continue }
            guard let plain = try? RelayCrypto.open(blob, key: key, objectKey: entry.key),
                  let manifest = try? JSONDecoder().decode(InboxManifest.self, from: plain)
            else {
                // Pacote estragado ou adulterado: fica lá, sem travar o resto.
                continue
            }
            guard manifest.protocolVersion <= SyncProtocol.version else {
                // De uma Caderneta mais nova: não dá pra ler com segurança.
                // Fica guardado até este app ser atualizado.
                result.newerVersionSeen = manifest.protocolVersion
                blockedMemoIDs.insert(entry.memoID)
                continue
            }
            pairing.deviceID = manifest.deviceId
            if !manifest.deviceName.isEmpty { pairing.phoneName = manifest.deviceName }

            var complete = true
            var keysToDelete: [String] = [entry.key]

            for item in manifest.items where item.kind == SyncProtocol.kindAudioMemo {
                guard let memoID = UUID(uuidString: item.id) else { continue }
                let audioKey = "inbox/\(item.id).m4a"

                if item.isDeleted == true {
                    // Apagada no celular: apaga aqui também.
                    if let memo = findMemo(memoID, in: modelContext) {
                        AudioStore.delete(fileName: memo.audioFileName)
                        modelContext.delete(memo)
                    }
                    if existingKeys.contains(audioKey) { keysToDelete.append(audioKey) }
                } else if item.isNew {
                    if findMemo(memoID, in: modelContext) == nil {
                        // O celular sobe o áudio antes do .json, mas se a
                        // conexão dele caiu no meio, o áudio pode faltar.
                        guard existingKeys.contains(audioKey),
                              let sealedAudio = try await client.get(audioKey),
                              let audio = try? RelayCrypto.open(sealedAudio, key: key, objectKey: audioKey)
                        else {
                            complete = false
                            blockedMemoIDs.insert(entry.memoID)
                            continue
                        }
                        let memo = try makeMemo(from: item, id: memoID, deviceID: manifest.deviceId, audio: audio, in: modelContext)
                        newMemos.append(memo)
                        result.imported += 1
                    }
                    // Já importada antes (a conexão caiu depois de salvar):
                    // não duplica, só limpa.
                    if existingKeys.contains(audioKey) { keysToDelete.append(audioKey) }
                } else if let memo = findMemo(memoID, in: modelContext) {
                    memo.title = item.title
                    memo.section = item.sectionId
                        .flatMap { UUID(uuidString: $0) }
                        .flatMap { findSection($0, in: modelContext) }
                }
                // Edição de uma fita que não existe mais aqui (apagada no
                // iPad): não há o que atualizar, só limpar.
            }

            guard complete else { continue }
            try modelContext.save()
            // Só apaga do servidor depois de salvar aqui.
            for objectKey in keysToDelete {
                try await client.delete(objectKey)
            }
        }

        // Em segundo plano ficam "pendentes" e a próxima rodada com o app
        // aberto transcreve (resumeTranscriptions).
        if transcribe {
            for memo in newMemos {
                MemoTranscription.start(memo, in: modelContext)
            }
        }
        return result
    }

    private func makeMemo(from item: InboxItemDTO, id: UUID, deviceID: String, audio: Data, in modelContext: ModelContext) throws -> AudioMemo {
        let fileName = "\(id.uuidString).m4a"
        try audio.write(to: AudioStore.url(for: fileName), options: FileProtection.writingOptions)

        let memo = AudioMemo(
            title: item.title,
            coverColor: NotebookColor(rawValue: item.coverColor) ?? .blue,
            audioFileName: fileName
        )
        // O mesmo id do celular: é assim que a transcrição acha o caminho de volta.
        memo.id = id
        memo.createdAt = Date(millisecondsSince1970: item.createdAt)
        memo.duration = TimeInterval(item.durationMs) / 1000
        memo.section = item.sectionId
            .flatMap { UUID(uuidString: $0) }
            .flatMap { findSection($0, in: modelContext) }
        memo.originDeviceID = deviceID
        modelContext.insert(memo)
        return memo
    }

    // MARK: Snapshot (iPad → celular)

    private struct SnapshotBody: Encodable {
        let sections: [SectionDTO]
        let memoUpdates: [MemoUpdateDTO]
        let deletedMemoIds: [String]
    }

    private static func snapshotHashKey(_ mailboxID: String) -> String {
        "sync.\(mailboxID).lastSnapshotHash"
    }

    private func publishSnapshot(for pairing: RelayPairing, client: RelayClient, modelContext: ModelContext) async throws {
        let body = try snapshotBody(for: pairing, modelContext)

        // Só sobe quando o conteúdo mudou — a rodada periódica quase sempre
        // termina aqui, sem gastar rede.
        let canonical = JSONEncoder()
        canonical.outputFormatting = [.sortedKeys]
        let canonicalData = try canonical.encode(body)
        let hash = Data(SHA256.hash(data: canonicalData)).hexString
        let hashKey = Self.snapshotHashKey(pairing.mailboxID)
        guard hash != UserDefaults.standard.string(forKey: hashKey) else { return }

        let snapshot = SnapshotDTO(
            protocolVersion: SyncProtocol.version,
            generatedAt: Date().millisecondsSince1970,
            sections: body.sections,
            memoUpdates: body.memoUpdates,
            deletedMemoIds: body.deletedMemoIds
        )
        let json = try JSONEncoder().encode(snapshot)
        let sealed = try RelayCrypto.seal(json, key: pairing.keys.encKey, objectKey: Self.snapshotKey)
        try await client.put(Self.snapshotKey, data: sealed)
        UserDefaults.standard.set(hash, forKey: hashKey)
    }

    private func snapshotBody(for pairing: RelayPairing, _ modelContext: ModelContext) throws -> SnapshotBody {
        let notebooks = try modelContext.fetch(FetchDescriptor<Notebook>(sortBy: [SortDescriptor(\.createdAt)]))
        var sections: [SectionDTO] = []
        // Cadernos protegidos (e os de coleções protegidas) não saem do iPad.
        for notebook in notebooks where !(notebook.isLocked || (notebook.group?.isLocked ?? false)) {
            for section in notebook.sortedSections {
                sections.append(SectionDTO(
                    id: section.id.uuidString,
                    notebookId: notebook.id.uuidString,
                    notebookTitle: notebook.title,
                    title: section.title,
                    order: section.order,
                    notebookColor: notebook.coverColor.rawValue
                ))
            }
        }

        // Só as fitas que vieram DESTE celular.
        guard let deviceID = pairing.deviceID else {
            return SnapshotBody(sections: sections, memoUpdates: [], deletedMemoIds: [])
        }
        let memos = try modelContext.fetch(FetchDescriptor<AudioMemo>(sortBy: [SortDescriptor(\.createdAt)]))
        let updates = memos.filter { $0.originDeviceID == deviceID }.map { memo in
            // Fita etiquetada num caderno protegido: o celular sabe que ela
            // chegou, mas o texto não volta.
            MemoUpdateDTO(
                id: memo.id.uuidString,
                title: memo.isProtected ? nil : memo.title,
                transcript: memo.isProtected ? nil : memo.transcript,
                transcriptionStatus: memo.transcriptionStatusRaw
            )
        }
        let deleted = Tombstones.memoIDs(deviceID: deviceID, maxAge: Self.tombstoneLifetime)
        return SnapshotBody(sections: sections, memoUpdates: updates, deletedMemoIds: deleted)
    }

    // MARK: Utilidades

    private func findMemo(_ id: UUID, in modelContext: ModelContext) -> AudioMemo? {
        var descriptor = FetchDescriptor<AudioMemo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func findSection(_ id: UUID, in modelContext: ModelContext) -> Section? {
        var descriptor = FetchDescriptor<Section>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

/// Fitas vindas de um celular e apagadas aqui, para avisar o celular.
/// Ficam no UserDefaults: são só ids, sem conteúdo.
private enum Tombstones {
    private static let key = "sync.tombstones"

    /// deviceID → (memoID → quando foi apagada, em segundos desde 1970)
    private static var all: [String: [String: Double]] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Double]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func add(memoID: String, deviceID: String) {
        var current = all
        current[deviceID, default: [:]][memoID] = Date().timeIntervalSince1970
        all = current
    }

    /// As ainda válidas, em ordem estável; as vencidas são descartadas.
    static func memoIDs(deviceID: String, maxAge: TimeInterval) -> [String] {
        var current = all
        let cutoff = Date().timeIntervalSince1970 - maxAge
        let alive = (current[deviceID] ?? [:]).filter { $0.value >= cutoff }
        if alive.count != current[deviceID]?.count {
            current[deviceID] = alive.isEmpty ? nil : alive
            all = current
        }
        return alive.keys.sorted()
    }

    static func clear(deviceID: String) {
        var current = all
        current[deviceID] = nil
        all = current
    }
}

/// `inbox/<memoId>-<updatedAt>.json` — os dados de uma fita numa versão.
private struct InboxEntry {
    let key: String
    let memoID: String
    let updatedAt: Int64

    init?(key: String) {
        let prefix = "inbox/", suffix = ".json"
        guard key.hasPrefix(prefix), key.hasSuffix(suffix) else { return nil }
        let name = key.dropFirst(prefix.count).dropLast(suffix.count)
        // O UUID tem hífens; o número de versão vem depois do último.
        guard let dash = name.lastIndex(of: "-"),
              let updatedAt = Int64(name[name.index(after: dash)...])
        else { return nil }
        self.key = key
        self.memoID = String(name[..<dash])
        self.updatedAt = updatedAt
    }
}

/// Mantém a sincronização rodando enquanto o app está aberto: uma rodada ao
/// voltar pro primeiro plano e depois a cada minuto. Em segundo plano para —
/// o iOS não deixaria rodar de qualquer jeito.
struct RelaySyncDriver: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await RelaySync.shared.syncNow(modelContext: modelContext)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
