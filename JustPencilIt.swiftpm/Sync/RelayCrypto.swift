import Foundation
import CryptoKit

/// Cifra de ponta a ponta da sincronização com a Caderneta (Android).
///
/// É a mesma de `reference/crypto.ts` no repo justpencilit-relay (PROTOCOL.md
/// §3) e de `RelayCrypto.kt` no Android: HKDF-SHA256 para derivar duas chaves
/// independentes da chave do pareamento, e AES-256-GCM com a chave do objeto
/// como dado autenticado. O servidor intermediário nunca vê a chave — só
/// guarda e repassa bytes que não consegue abrir.
///
/// Como o Swift Playgrounds não roda testes, o `selfTest()` confere os
/// vetores fixos do protocolo no próprio iPad antes de cada pareamento: se
/// uma atualização do CryptoKit mudasse algo, o pareamento falha em vez de
/// gerar pacotes que o celular não abre.
enum RelayCrypto {
    static let blobVersion: UInt8 = 0x01
    static let nonceBytes = 12
    static let tagBytes = 16

    struct Keys {
        /// Vai no `Authorization: Bearer`. O servidor guarda só o hash.
        let token: String
        /// AES-256-GCM. Nunca sai dos aparelhos.
        let encKey: SymmetricKey
    }

    enum CryptoError: Error {
        case badBlob
        case unsupportedVersion
    }

    static func deriveKeys(masterKey: Data, mailboxID: String) -> Keys {
        let ikm = SymmetricKey(data: masterKey)
        let salt = Data(mailboxID.utf8)
        let tokenKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: Data("justpencilit relay auth v1".utf8),
            outputByteCount: 32
        )
        let encKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: Data("justpencilit relay enc v1".utf8),
            outputByteCount: 32
        )
        let tokenData = tokenKey.withUnsafeBytes { Data($0) }
        return Keys(token: tokenData.base64URLEncodedString(), encKey: encKey)
    }

    /// `[versão 0x01][nonce 12][texto cifrado][tag 16]`, com a chave do objeto
    /// como AAD: o servidor não consegue trocar um pacote de lugar.
    static func seal(_ plaintext: Data, key: SymmetricKey, objectKey: String, nonce: AES.GCM.Nonce = AES.GCM.Nonce()) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: Data(objectKey.utf8))
        var out = Data([blobVersion])
        nonce.withUnsafeBytes { out.append(contentsOf: $0) }
        out.append(box.ciphertext)
        out.append(box.tag)
        return out
    }

    /// Lança erro se o pacote foi adulterado ou veio de outra chave.
    static func open(_ blob: Data, key: SymmetricKey, objectKey: String) throws -> Data {
        // Array evita surpresas com índices de fatias de `Data`.
        let bytes = [UInt8](blob)
        guard bytes.count >= 1 + nonceBytes + tagBytes else { throw CryptoError.badBlob }
        guard bytes[0] == blobVersion else { throw CryptoError.unsupportedVersion }
        let nonce = try AES.GCM.Nonce(data: Data(bytes[1..<(1 + nonceBytes)]))
        let ciphertext = Data(bytes[(1 + nonceBytes)..<(bytes.count - tagBytes)])
        let tag = Data(bytes[(bytes.count - tagBytes)...])
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(box, using: key, authenticating: Data(objectKey.utf8))
    }

    /// Confere os vetores de PROTOCOL.md §3.4 (gerados pela referência em
    /// TypeScript e conferidos também no Android).
    static func selfTest() -> Bool {
        let master = Data((0..<32).map { UInt8($0) })
        let mailbox = "AAECAwQFBgcICQoLDA0ODw"
        let keys = deriveKeys(masterKey: master, mailboxID: mailbox)
        guard keys.token == "ZtymvVeYTWbnvYBV08ixgR8JhCpWVe8dhvwzUGYkkyE" else { return false }

        let encHex = keys.encKey.withUnsafeBytes { Data($0) }.hexString
        guard encHex == "fa1170c6737887a0dd37398ea281947f7049750ac51fb9e8b3d605c1ac5234b3" else { return false }

        guard let nonce = try? AES.GCM.Nonce(data: Data((0..<12).map { UInt8(0xa0 + $0) })),
              let blob = try? seal(Data("JustPencilIt".utf8), key: keys.encKey, objectKey: "snapshot/manifest", nonce: nonce)
        else { return false }
        guard blob.hexString == "01a0a1a2a3a4a5a6a7a8a9aaaba6695da556fcbd10c3d126883263b5f59be18e14816d7994d0ddf0ea" else {
            return false
        }
        guard let opened = try? open(blob, key: keys.encKey, objectKey: "snapshot/manifest"),
              opened == Data("JustPencilIt".utf8)
        else { return false }
        // E um pacote movido de lugar tem que falhar.
        return (try? open(blob, key: keys.encKey, objectKey: "snapshot/outro")) == nil
    }
}

/// O conteúdo do QR mostrado nos Ajustes (PROTOCOL.md §2).
struct RelayPairingCode {
    let relayURL: String
    let mailboxID: String
    let masterKey: Data
    let peerName: String?

    /// Caixa nova: 16 bytes aleatórios de id e 32 de chave-mestra.
    static func generate(relayURL: String, peerName: String?) -> RelayPairingCode {
        RelayPairingCode(
            relayURL: relayURL,
            mailboxID: randomBytes(16).base64URLEncodedString(),
            masterKey: randomBytes(32),
            peerName: peerName
        )
    }

    var text: String {
        var items = [
            ("v", "1"),
            ("relay", relayURL),
            ("m", mailboxID),
            ("k", masterKey.base64URLEncodedString()),
        ]
        if let peerName, !peerName.isEmpty {
            items.append(("n", peerName))
        }
        // Tudo que não é letra, número ou `-._~` vira %XX — inclusive o ":"
        // e as "/" do endereço do relay, para não haver ambiguidade.
        let query = items
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: .urlValueAllowed) ?? "")" }
            .joined(separator: "&")
        return "justpencilit://pair?\(query)"
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "Sem gerador aleatório seguro")
        return Data(bytes)
    }
}

extension CharacterSet {
    /// Só letras, números e `-._~`: o resto vira `%XX` no valor do QR.
    static let urlValueAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
