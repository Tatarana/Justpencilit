import Foundation
import Security

/// Um celular pareado. Cada celular tem a própria caixa no relay, com a
/// própria chave: desparear um não afeta os outros.
struct RelayPairing: Codable, Identifiable {
    let relayURL: String
    let mailboxID: String
    let masterKey: Data
    let pairedAt: Date
    /// O id que o celular usa nos pacotes — aprendido no primeiro contato
    /// (`device/info` ou a primeira fita). É o que liga as fitas ao celular.
    var deviceID: String?
    /// Como o celular se apresenta (ex.: "Pixel 8").
    var phoneName: String?

    var id: String { mailboxID }

    var code: RelayPairingCode {
        RelayPairingCode(relayURL: relayURL, mailboxID: mailboxID, masterKey: masterKey, peerName: PairingStore.ownName)
    }

    var keys: RelayCrypto.Keys {
        RelayCrypto.deriveKeys(masterKey: masterKey, mailboxID: mailboxID)
    }

    var client: RelayClient? {
        guard let url = URL(string: relayURL) else { return nil }
        return RelayClient(baseURL: url, mailboxID: mailboxID, token: keys.token)
    }

    var displayName: String { phoneName ?? "Celular sem nome ainda" }
}

/// Guarda os pareamentos no Keychain, só neste aparelho
/// (`AfterFirstUnlockThisDeviceOnly`): não vai pro backup do iCloud nem pro
/// Keychain do iCloud — as chaves só existem neste iPad e nos celulares.
/// "After first unlock" (e não "when unlocked") para a sincronização poder
/// rodar com a tela apagada logo depois de usar o app.
enum PairingStore {
    private static let service = "com.tatarana.justpencilit.relay"
    private static let account = "pairings"
    /// Versão de um celular só (antes de existir a lista).
    private static let legacyAccount = "pairing"

    /// Nome deste iPad no QR (o iOS devolve só "iPad" sem permissão especial).
    static var ownName: String { "JustPencilIt do iPad" }

    static func load() -> [RelayPairing] {
        if let data = read(account), let list = try? JSONDecoder().decode([RelayPairing].self, from: data) {
            return list
        }
        // Migra o formato antigo, de um celular só.
        if let data = read(legacyAccount), let single = try? JSONDecoder().decode(RelayPairing.self, from: data) {
            if (try? save([single])) != nil { delete(legacyAccount) }
            return [single]
        }
        return []
    }

    static func save(_ pairings: [RelayPairing]) throws {
        let data = try JSONEncoder().encode(pairings)
        delete(account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func read(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
