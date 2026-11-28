import Foundation
import Security

/// O pareamento com a Caderneta. Por enquanto, um celular por iPad.
struct RelayPairing: Codable {
    let relayURL: String
    let mailboxID: String
    let masterKey: Data
    let pairedAt: Date

    var code: RelayPairingCode {
        RelayPairingCode(relayURL: relayURL, mailboxID: mailboxID, masterKey: masterKey, peerName: PairingStore.ownName)
    }

    var client: RelayClient? {
        guard let url = URL(string: relayURL) else { return nil }
        let keys = RelayCrypto.deriveKeys(masterKey: masterKey, mailboxID: mailboxID)
        return RelayClient(baseURL: url, mailboxID: mailboxID, token: keys.token)
    }

    var keys: RelayCrypto.Keys {
        RelayCrypto.deriveKeys(masterKey: masterKey, mailboxID: mailboxID)
    }
}

/// Guarda o pareamento no Keychain, só neste aparelho
/// (`AfterFirstUnlockThisDeviceOnly`): não vai pro backup do iCloud nem
/// pro Keychain do iCloud — a chave só existe neste iPad e no celular.
/// "After first unlock" (e não "when unlocked") para a sincronização poder
/// rodar com a tela apagada logo depois de usar o app.
enum PairingStore {
    private static let service = "com.tatarana.justpencilit.relay"
    private static let account = "pairing"

    /// Nome deste iPad no QR (o iOS devolve só "iPad" sem permissão especial).
    static var ownName: String { "JustPencilIt do iPad" }

    static func load() -> RelayPairing? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(RelayPairing.self, from: data)
    }

    static func save(_ pairing: RelayPairing) throws {
        clear()
        let data = try JSONEncoder().encode(pairing)
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

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
