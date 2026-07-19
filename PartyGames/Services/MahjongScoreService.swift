import Foundation

enum MahjongScoreServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)
    case unreachable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "后端地址无效"
        case .invalidResponse:
            return "服务器返回异常，请稍后重试"
        case .server(let message):
            return message
        case .unreachable:
            return "服务器连接超时，请切换网络或关闭代理后重试"
        }
    }
}

struct MahjongScoreService: Sendable {
    static let shared = MahjongScoreService()

    private let preferredBaseURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let session: URLSession

    init(baseURL: URL = MahjongScoreEndpoint.baseURL, session: URLSession? = nil) {
        self.preferredBaseURL = baseURL
        if let session {
            self.session = session
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 18
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    func createRoom(_ request: MahjongCreateRoomRequest) async throws -> MahjongRoomResponse {
        try await post(path: "rooms", body: request)
    }

    func joinRoom(code: String, request: MahjongJoinRoomRequest) async throws -> MahjongRoomResponse {
        try await post(
            path: "rooms/\(code.uppercased())/join",
            body: request,
            bearerToken: MahjongMemberTokenStore.token(for: code)
        )
    }

    func loadUnfinishedRooms(deviceId: String) async throws -> MahjongRoomHistoryResponse {
        try await get(path: "history", queryItems: [
            URLQueryItem(name: "deviceId", value: deviceId),
        ])
    }

    func loadRoom(code: String) async throws -> MahjongRoomSnapshot {
        try await get(path: "rooms/\(code.uppercased())")
    }

    func settleRoom(code: String, memberToken: String, multiplier: Double) async throws -> MahjongSettleRoomResponse {
        try await post(
            path: "rooms/\(code.uppercased())/settle",
            body: MahjongSettleRoomRequest(multiplier: multiplier),
            bearerToken: memberToken
        )
    }

    func dismissRoom(code: String, memberToken: String) async throws {
        _ = try await endRoom(code: code, memberToken: memberToken)
    }

    func endRoom(code: String, memberToken: String) async throws -> MahjongSettleRoomResponse {
        try await post(
            path: "rooms/\(code.uppercased())/end",
            body: EmptyRequest(),
            bearerToken: memberToken
        )
    }

    func inviteURL(roomCode: String) throws -> URL {
        guard var components = URLComponents(url: MahjongScoreEndpoint.webBaseURL, resolvingAgainstBaseURL: false) else {
            throw MahjongScoreServiceError.invalidURL
        }
        // 规范成 https://host/?room=CODE，兼顾系统相机与微信扫码识别。
        if components.path.isEmpty {
            components.path = "/"
        }
        components.queryItems = [
            URLQueryItem(name: "room", value: roomCode.uppercased()),
        ]
        components.fragment = nil

        guard let url = components.url,
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            throw MahjongScoreServiceError.invalidURL
        }

        return url
    }

    func webSocketURL(roomCode: String, memberToken: String) throws -> URL {
        // WebSocket 直连 Worker；Netlify 反代不支持升级。
        let wsBase = MahjongScoreEndpoint.webSocketBaseURL
        guard var components = URLComponents(url: wsBase, resolvingAgainstBaseURL: false) else {
            throw MahjongScoreServiceError.invalidURL
        }

        components.scheme = wsBase.scheme == "http" ? "ws" : "wss"
        let trimmed = wsBase.path.hasSuffix("/") ? String(wsBase.path.dropLast()) : wsBase.path
        components.path = "\(trimmed)/rooms/\(roomCode.uppercased())/ws"
        components.queryItems = [
            URLQueryItem(name: "memberToken", value: memberToken),
        ]

        guard let url = components.url else {
            throw MahjongScoreServiceError.invalidURL
        }

        return url
    }

    private func get<ResponseBody: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> ResponseBody {
        try await withEndpointFallback { baseURL in
            var components = URLComponents(url: resolve(path: path, baseURL: baseURL), resolvingAgainstBaseURL: false)
            if !queryItems.isEmpty {
                components?.queryItems = queryItems
            }
            guard let url = components?.url else {
                throw MahjongScoreServiceError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 12
            return try await send(request)
        }
    }

    private func post<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody,
        bearerToken: String? = nil
    ) async throws -> ResponseBody {
        try await withEndpointFallback { baseURL in
            var request = URLRequest(url: resolve(path: path, baseURL: baseURL))
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            if let bearerToken {
                request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "authorization")
            }
            request.httpBody = try encoder.encode(body)
            return try await send(request)
        }
    }

    private func send<ResponseBody: Decodable>(_ request: URLRequest) async throws -> ResponseBody {
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw MahjongScoreServiceError.invalidResponse
        }
    }

    private func withEndpointFallback<T>(
        _ operation: (URL) async throws -> T
    ) async throws -> T {
        var lastError: Error = MahjongScoreServiceError.unreachable

        for baseURL in MahjongScoreEndpoint.candidateBaseURLs(preferred: preferredBaseURL) {
            do {
                return try await operation(baseURL)
            } catch let error as MahjongScoreServiceError {
                lastError = error
                // 明确业务错误不换端点；网关/格式异常继续尝试。
                if case .server = error {
                    throw error
                }
                continue
            } catch {
                lastError = error
                if Self.isRetryableNetworkError(error) {
                    continue
                }
                throw error
            }
        }

        throw lastError
    }

    private func resolve(path: String, baseURL: URL) -> URL {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let root = baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appendingPathComponent("")
        return root.appendingPathComponent(trimmed)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MahjongScoreServiceError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ServerError.self, from: data).error) ?? "请求失败，请稍后再试"
            throw MahjongScoreServiceError.server(message)
        }

        // Netlify SPA / 代理错误页常返回 200 + HTML，不能当 JSON 解。
        if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("text/html") {
            throw MahjongScoreServiceError.invalidResponse
        }
        if data.first == UInt8(ascii: "<") {
            throw MahjongScoreServiceError.invalidResponse
        }
    }

    private static func isRetryableNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch nsError.code {
        case NSURLErrorTimedOut,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorSecureConnectionFailed,
             NSURLErrorDNSLookupFailed,
             NSURLErrorInternationalRoamingOff:
            return true
        default:
            return false
        }
    }
}

private struct ServerError: Decodable {
    var error: String
}

private struct EmptyRequest: Encodable {}

enum MahjongScoreEndpoint {
    static var baseURL: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "MahjongScoreBaseURL") as? String,
           let url = URL(string: value),
           url.scheme != nil,
           url.host != nil {
            return url
        }

        return URL(string: "https://party-games-mahjong-join.netlify.app/api")!
    }

    static var webSocketBaseURL: URL {
        URL(string: "https://mahjong-score-worker.d03054144.workers.dev")!
    }

    static var webBaseURL: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "MahjongWebBaseURL") as? String,
           let url = URL(string: value),
           url.scheme != nil,
           url.host != nil {
            return url
        }

        return URL(string: "https://party-games-mahjong-join.netlify.app")!
    }

    static func candidateBaseURLs(preferred: URL) -> [URL] {
        // 优先只用 Netlify；失败时再试 Worker，避免每次请求串行打多个慢端点。
        let urls = [
            preferred,
            URL(string: "https://party-games-mahjong-join.netlify.app/api")!,
            URL(string: "https://mahjong-score-worker.d03054144.workers.dev")!,
        ]

        var seen = Set<String>()
        return urls.filter { url in
            let key = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return seen.insert(key).inserted
        }
    }
}
