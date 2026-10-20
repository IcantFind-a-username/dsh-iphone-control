import Foundation

enum PocketDefaults {
    /// Baked in at build time via the POCKET_BASE_URL / POCKET_TOKEN build
    /// settings (see Config/Info.plist), so this repository never carries a
    /// real host or token. Both stay editable on the pairing screen.
    static var baseURL: String {
        let value = (Bundle.main.object(forInfoDictionaryKey: "PocketBaseURL") as? String) ?? ""
        return value.isEmpty ? "http://100.x.y.z:8931/pocket" : value
    }

    static var token: String {
        (Bundle.main.object(forInfoDictionaryKey: "PocketToken") as? String) ?? ""
    }
}

struct PocketAPI {
    let base: URL
    let token: String

    init?(baseURLString: String, token: String) {
        var text = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host != nil else { return nil }
        self.base = url
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await raw(path, method: "GET", query: query, body: nil)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PocketError.message("无法解析服务器响应")
        }
    }

    func data(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        try await raw(path, method: "GET", query: query, body: nil)
    }

    func post<T: Decodable>(_ path: String, json: [String: Any]) async throws -> T {
        try await request(path, method: "POST", query: [], body: json)
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String,
        query: [URLQueryItem],
        body: [String: Any]?
    ) async throws -> T {
        let data = try await raw(path, method: method, query: query, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PocketError.message("无法解析服务器响应")
        }
    }

    private func raw(
        _ path: String,
        method: String,
        query: [URLQueryItem],
        body: [String: Any]?
    ) async throws -> Data {
        var components = URLComponents(
            url: base.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw PocketError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue(token, forHTTPHeaderField: "x-pocket-token")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if let failure = try? JSONDecoder().decode(SimpleResponse.self, from: data),
               let message = failure.error {
                throw PocketError.message(message)
            }
            if http.statusCode == 401 { throw PocketError.message("配对已失效，请在设置里重新配对") }
            throw PocketError.message("服务器返回 \(http.statusCode)")
        }
        return data
    }
}

struct OlderResponse: Codable {
    var ok: Bool
    var items: [PocketItem]
    var hasMore: Bool?
    var rev: Int?
}
