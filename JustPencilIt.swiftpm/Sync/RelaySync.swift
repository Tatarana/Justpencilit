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
/// O iPad continua sendo a central: ele **importa** as fitas que o celular
/// deixou na caixa de entrada (`inbox/`), transcreve, e **publica** uma cópia
/// de leitura (`snapshot/manifest`) com as seções e as transcrições. Tudo
/// sobe e desce cifrado (`RelayCrypto`); o servidor não lê nada.
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

    private(set) var status: Status = .idle
    private(set) var pairing: RelayPairing? = PairingStore.load()
    /// Nome do celular, como ele mesmo se apresenta nos pacotes.
    private(set) var phoneName: String? = UserDefaults.standard.string(forKey: Defaults.phoneName)

    var isPaired: Bool { pairing != nil }

    private enum Defaults {
        static let lastSnapshotHash = "sync.lastSnapshotHash"
        static let phoneName = "sync.phoneName"
    }

    private static let snapshotKey = "snapshot/manifest"

    // MARK: - Pareamento

    /// Cria uma caixa nova no relay e devolve o código para o QR.
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
        try PairingStore.save(newPairing)

        pairing = newPairing
        UserDefaults.standard.removeObject(forKey: Defaults.lastSnapshotHash)
        setPhoneName(nil)
        status = .idle
        return code
    }

    /// Apaga a caixa no relay e esquece o celular. Devolve `false` se não deu
    /// pra apagar no servidor (sem internet) — o pareamento local some mesmo
    /// assim, e a caixa órfã fica inacessível sem a chave.
    func unpair() async -> Bool {
        guard let pairing else { return true }
        var deletedOnServer = true
        do {
            try await pairing.client?.deleteMailbox()
        } catch {
            deletedOnServer = false
        }
        PairingStore.clear()
        self.pairing = nil
        UserDefaults.standard.removeObject(forKey: Defaults.lastSnapshotHash)
        setPhoneName(nil)
        status = .idle
        return deletedOnServer
    }

    // MARK: - Sincronização

    /// Uma rodada: importa a caixa de entrada e publica o snapshot se mudou.
    /// Barato quando não há nada novo (uma listagem e nenhum envio).
    func syncNow(modelContext: ModelContext) async {
        guard let pairing, let client = pairing.client, status != .running else { return }
        status = .running
        let key = pairing.keys.encKey
        do {
            let imported = try await importInbox(client: client, key: key, modelContext: modelContext)
            try await publishSnapshot(client: client, key: key, modelContext: modelContext)
            status = .done(at: Date(), imported: imported)
        } catch let error as RelayError {
            switch error {
            case .unreachable:
                status = .offline
            case .http:
                status = .failed(error.isPairingRevoked
                    ? "O pareamento não vale mais no servidor. Desfaça e pareie o celular de novo."
                    : (error.errorDescription ?? "Erro no servidor."))
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Publica o snapshot sem mexer no status — usado quando uma transcrição
    /// termina, para o texto chegar ao celular sem esperar a próxima rodada.
    private func publishQuietly(modelContext: ModelContext) async {
        guard let pairing, let client = pairing.client else { return }
        try? await publishSnapshot(client: client, key: pairing.keys.encKey, modelContext: modelContext)
    }

    // MARK: Caixa de entrada (celular → iPad)

    private func importInbox(client: RelayClient, key: SymmetricKey, modelContext: ModelContext) async throws -> Int {
        let objects = try await client.list(prefix: "inbox/")
        let existingKeys = Set(objects.map(\.key))
        // Em ordem de edição: a fita nova chega antes das renomeações dela.
        let entries = objects.compactMap { InboxEntry(key: $0.key) }.sorted { $0.updatedAt < $1.updatedAt }

        var imported = 0
        var newMemos: [AudioMemo] = []
        // Fitas cujo áudio ainda não chegou: as edições seguintes delas
        // esperam também, para não serem aplicadas antes da fita existir.
        var blockedMemoIDs: Set<String> = []

        for entry in entries {
            if blockedMemoIDs.contains(entry.memoID) { continue }
            guard let blob = try await client.get(entry.key) else { continue }
            guard let plain = try? RelayCrypto.open(blob, key: key, objectKey: entry.key),
                  let manifest = try? JSONDecoder().decode(InboxManifest.self, from: plain),
                  manifest.protocolVersion <= SyncProtocol.version
            else {
                // Pacote estragado, adulterado ou de uma versão mais nova do
                // app: fica lá, sem travar o resto.
                continue
            }
            if !manifest.deviceName.isEmpty { setPhoneName(manifest.deviceName) }

            var complete = true
            var audioKeysToDelete: [String] = []

            for item in manifest.items where item.kind == SyncProtocol.kindAudioMemo {
                guard let memoID = UUID(uuidString: item.id) else { continue }
                let audioKey = "inbox/\(item.id).m4a"

                if item.isNew {
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
                        imported += 1
                    }
                    // Já importada antes (a conexão caiu depois de salvar):
                    // não duplica, só limpa.
                    if existingKeys.contains(audioKey) { audioKeysToDelete.append(audioKey) }
                } else if let memo = findMemo(memoID, in: modelContext) {
                    memo.title = item.title
                    memo.section = item.sectionId
                        .flatMap { UUID(uuidString: $0) }
                        .flatMap { findSection($0, in: modelContext) }
                }
                // isNew = false de uma fita que não existe mais aqui (apagada
                // no iPad): não há o que atualizar, só limpar.
            }

            guard complete else { continue }
            try modelContext.save()
            // Só apaga do servidor depois de salvar aqui.
            try await client.delete(entry.key)
            for audioKey in audioKeysToDelete {
                try await client.delete(audioKey)
            }
        }

        for memo in newMemos {
            transcribe(memo, modelContext: modelContext)
        }
        return imported
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

    private func transcribe(_ memo: AudioMemo, modelContext: ModelContext) {
        let memoID = memo.id
        let fileURL = AudioStore.url(for: memo.audioFileName)
        memo.transcriptionStatus = .transcribing
        Task { @MainActor in
            var text: String?
            do {
                text = try await SpeechTranscriptionService.transcribe(fileURL: fileURL)
            } catch {
                text = nil
            }
            guard let memo = self.findMemo(memoID, in: modelContext) else { return }
            if let text {
                memo.transcript = text
                memo.transcriptionStatus = .done
            } else {
                memo.transcriptionStatus = .failed
            }
            try? modelContext.save()
            await self.publishQuietly(modelContext: modelContext)
        }
    }

    // MARK: Snapshot (iPad → celular)

    private struct SnapshotBody: Encodable {
        let sections: [SectionDTO]
        let memoUpdates: [MemoUpdateDTO]
    }

    private func publishSnapshot(client: RelayClient, key: SymmetricKey, modelContext: ModelContext) async throws {
        let body = try snapshotBody(modelContext)

        // Só sobe quando o conteúdo mudou — a rodada periódica quase sempre
        // termina aqui, sem gastar rede.
        let canonical = JSONEncoder()
        canonical.outputFormatting = [.sortedKeys]
        let canonicalData = try canonical.encode(body)
        let hash = Data(SHA256.hash(data: canonicalData)).hexString
        guard hash != UserDefaults.standard.string(forKey: Defaults.lastSnapshotHash) else { return }

        let snapshot = SnapshotDTO(
            protocolVersion: SyncProtocol.version,
            generatedAt: Date().millisecondsSince1970,
            sections: body.sections,
            memoUpdates: body.memoUpdates
        )
        let json = try JSONEncoder().encode(snapshot)
        let sealed = try RelayCrypto.seal(json, key: key, objectKey: Self.snapshotKey)
        try await client.put(Self.snapshotKey, data: sealed)
        UserDefaults.standard.set(hash, forKey: Defaults.lastSnapshotHash)
    }

    private func snapshotBody(_ modelContext: ModelContext) throws -> SnapshotBody {
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

        let memos = try modelContext.fetch(FetchDescriptor<AudioMemo>(sortBy: [SortDescriptor(\.createdAt)]))
        let updates = memos.filter { $0.originDeviceID != nil }.map { memo in
            // Fita etiquetada num caderno protegido: o celular sabe que ela
            // chegou, mas o texto não volta.
            MemoUpdateDTO(
                id: memo.id.uuidString,
                title: memo.isProtected ? nil : memo.title,
                transcript: memo.isProtected ? nil : memo.transcript,
                transcriptionStatus: memo.transcriptionStatusRaw
            )
        }
        return SnapshotBody(sections: sections, memoUpdates: updates)
    }

    // MARK: Utilidades

    private func setPhoneName(_ name: String?) {
        phoneName = name
        if let name {
            UserDefaults.standard.set(name, forKey: Defaults.phoneName)
        } else {
            UserDefaults.standard.removeObject(forKey: Defaults.phoneName)
        }
    }

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
