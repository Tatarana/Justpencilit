import Foundation

enum RelayError: Error, LocalizedError {
    /// Sem internet, servidor fora do ar, tempo esgotado. Tenta na próxima.
    case unreachable(Error)
    /// O relay respondeu, mas recusou.
    case http(status: Int, code: String?)

    /// A caixa sumiu ou o token não vale mais.
    var isPairingRevoked: Bool {
        if case let .http(status, code) = self {
            return status == 403 || code == "mailbox_not_found"
        }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .unreachable:
            return "Sem conexão com o servidor."
        case let .http(status, code):
            return "O servidor recusou (\(status)\(code.map { ", \($0)" } ?? ""))."
        }
    }
}

struct RelayObject: Decodable {
    let key: String
    let size: Int
    let etag: String
    let uploaded: String
}

/// HTTP cru com o relay na Cloudflare (PROTOCOL.md §4). Não sabe nada de
/// cifra: só leva e traz bytes.
struct RelayClient {
    let baseURL: URL
    let mailboxID: String
    let token: String

    private var mailboxURL: URL {
        baseURL.appendingPathComponent("v1").appendingPathComponent("mailboxes").appendingPathComponent(mailboxID)
    }

    private func objectURL(_ key: String) -> URL {
        // As chaves só têm [A-Za-z0-9._-] e "/", então nada precisa de escape.
        key.split(separator: "/").reduce(mailboxURL.appendingPathComponent("objects")) {
            $0.appendingPathComponent(String($1))
        }
    }

    /// Registra a caixa. Repetir com o mesmo token é inofensivo.
    func register() async throws {
        _ = try await send("PUT", mailboxURL)
    }

    /// Apaga a caixa e tudo dentro (despareamento).
    func deleteMailbox() async throws {
        _ = try await send("DELETE", mailboxURL)
    }

    func list(prefix: String) async throws -> [RelayObject] {
        struct Page: Decodable {
            let objects: [RelayObject]
            let cursor: String?
        }
        var all: [RelayObject] = []
        var cursor: String?
        repeat {
            var components = URLComponents(url: mailboxURL.appendingPathComponent("objects"), resolvingAgainstBaseURL: false)!
            var query = [URLQueryItem(name: "prefix", value: prefix)]
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            components.queryItems = query
            let data = try await send("GET", components.url!)
            let page = try JSONDecoder().decode(Page.self, from: data)
            all += page.objects
            cursor = page.cursor
        } while cursor != nil
        return all
    }

    /// `nil` se o pacote não existe.
    func get(_ key: String) async throws -> Data? {
        do {
            return try await send("GET", objectURL(key))
        } catch RelayError.http(let status, let code) where status == 404 && code == "object_not_found" {
            return nil
        }
    }

    func put(_ key: String, data: Data) async throws {
        _ = try await send("PUT", objectURL(key), body: data)
    }

    func delete(_ key: String) async throws {
        _ = try await send("DELETE", objectURL(key))
    }

    private func send(_ method: String, _ url: URL, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw RelayError.unreachable(error)
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else {
            throw RelayError.unreachable(URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            struct ErrorBody: Decodable { let error: String? }
            let code = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw RelayError.http(status: http.statusCode, code: code)
        }
        return data
    }
}
