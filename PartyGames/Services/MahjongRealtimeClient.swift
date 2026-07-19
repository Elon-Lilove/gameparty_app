import Foundation

@MainActor
final class MahjongRealtimeClient {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var isManuallyDisconnected = true
    private var currentURL: URL?
    private var onSnapshot: (@Sendable (MahjongRoomSnapshot, MahjongRealtimeAcknowledgement?) -> Void)?
    private var onStatus: (@Sendable (MahjongRealtimeConnectionState) -> Void)?
    private var onError: (@Sendable (String, MahjongRealtimeAcknowledgement?) -> Void)?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(
        url: URL,
        onSnapshot: @escaping @Sendable (MahjongRoomSnapshot, MahjongRealtimeAcknowledgement?) -> Void,
        onStatus: @escaping @Sendable (MahjongRealtimeConnectionState) -> Void,
        onError: @escaping @Sendable (String, MahjongRealtimeAcknowledgement?) -> Void
    ) {
        disconnect()
        isManuallyDisconnected = false
        reconnectAttempt = 0
        currentURL = url
        self.onSnapshot = onSnapshot
        self.onStatus = onStatus
        self.onError = onError

        openSocket()
    }

    private func openSocket() {
        guard let currentURL else { return }

        receiveTask?.cancel()
        heartbeatTask?.cancel()
        reconnectTask?.cancel()

        onStatus?(.connecting)
        let socket = session.webSocketTask(with: currentURL)
        task = socket
        socket.resume()
        startHeartbeat(socket: socket)

        let decoder = JSONDecoder()
        receiveTask = Task { [weak socket] in
            guard let socket else { return }

            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    guard let data = message.dataValue else { continue }
                    let envelope = try decoder.decode(MahjongRealtimeEnvelope.self, from: data)

                    if envelope.type == "state", let snapshot = envelope.snapshot {
                        await MainActor.run {
                            self.reconnectAttempt = 0
                            self.onSnapshot?(snapshot, envelope.acknowledgement)
                            self.onStatus?(.connected)
                        }
                    } else if envelope.type == "error", let error = envelope.error {
                        await MainActor.run {
                            self.onError?(error, envelope.acknowledgement)
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.handleSocketFailure(error.localizedDescription)
                        }
                    }
                    return
                }
            }
        }
    }

    func sendAdjustScore(playerId: String, delta: Int, operationId: String? = nil) async throws {
        let message = MahjongRealtimeMessage(
            type: "adjust_score",
            playerId: playerId,
            delta: delta,
            reason: nil,
            name: nil,
            targetDeviceId: nil,
            targetPlayerId: nil,
            amount: nil,
            operationId: operationId
        )
        try await send(message)
    }

    func sendGiveScore(targetPlayerId: String, amount: Int, operationId: String? = nil) async throws {
        let message = MahjongRealtimeMessage(
            type: "give_score",
            playerId: nil,
            delta: nil,
            reason: nil,
            name: nil,
            targetDeviceId: nil,
            targetPlayerId: targetPlayerId,
            amount: amount,
            operationId: operationId
        )
        try await send(message)
    }

    func sendRenamePlayer(playerId: String, name: String, operationId: String? = nil) async throws {
        let message = MahjongRealtimeMessage(
            type: "rename_player",
            playerId: playerId,
            delta: nil,
            reason: nil,
            name: name,
            targetDeviceId: nil,
            targetPlayerId: nil,
            amount: nil,
            operationId: operationId
        )
        try await send(message)
    }

    func sendAddPlayer(name: String, operationId: String? = nil) async throws {
        let message = MahjongRealtimeMessage(
            type: "add_player",
            playerId: nil,
            delta: nil,
            reason: nil,
            name: name,
            targetDeviceId: nil,
            targetPlayerId: nil,
            amount: nil,
            operationId: operationId
        )
        try await send(message)
    }

    func sendRemovePlayer(playerId: String, operationId: String? = nil) async throws {
        let message = MahjongRealtimeMessage(
            type: "remove_player",
            playerId: playerId,
            delta: nil,
            reason: nil,
            name: nil,
            targetDeviceId: nil,
            targetPlayerId: nil,
            amount: nil,
            operationId: operationId
        )
        try await send(message)
    }

    func sendTableScore(amount: Int, operationId: String? = nil) async throws {
        let message = MahjongRealtimeMessage(
            type: "table_score",
            playerId: nil,
            delta: nil,
            reason: nil,
            name: nil,
            targetDeviceId: nil,
            targetPlayerId: nil,
            amount: amount,
            operationId: operationId
        )
        try await send(message)
    }

    func sendTransferOwner(targetDeviceId: String, operationId: String? = nil) async throws {
        let message = MahjongRealtimeMessage(
            type: "transfer_owner",
            playerId: nil,
            delta: nil,
            reason: nil,
            name: nil,
            targetDeviceId: targetDeviceId,
            targetPlayerId: nil,
            amount: nil,
            operationId: operationId
        )
        try await send(message)
    }

    func disconnect() {
        isManuallyDisconnected = true
        reconnectTask?.cancel()
        reconnectTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        currentURL = nil
        onSnapshot = nil
        onStatus = nil
        onError = nil
    }

    private func send(_ message: MahjongRealtimeMessage) async throws {
        guard let task else {
            throw MahjongRealtimeClientError.disconnected
        }

        let data = try encoder.encode(message)
        try await task.send(.data(data))
    }

    private func startHeartbeat(socket: URLSessionWebSocketTask) {
        heartbeatTask = Task { [weak socket] in
            guard let socket else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }

                do {
                    try await socket.send(.string(#"{"type":"ping"}"#))
                } catch {
                    await MainActor.run {
                        self.handleSocketFailure(error.localizedDescription)
                    }
                    return
                }
            }
        }
    }

    private func handleSocketFailure(_ message: String) {
        guard !isManuallyDisconnected else { return }

        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil

        reconnectAttempt += 1
        let delay = min(12, max(1, reconnectAttempt * 2))
        onStatus?(.reconnecting)
        onError?("同步连接不稳定，正在自动重连", nil)

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await MainActor.run {
                self?.openSocket()
            }
        }
    }
}

enum MahjongRealtimeConnectionState: Equatable, Sendable {
    case connecting
    case connected
    case reconnecting
}

enum MahjongRealtimeClientError: LocalizedError {
    case disconnected

    var errorDescription: String? {
        switch self {
        case .disconnected:
            return "同步连接正在恢复，请稍后再试"
        }
    }
}

private extension URLSessionWebSocketTask.Message {
    var dataValue: Data? {
        switch self {
        case .data(let data):
            return data
        case .string(let string):
            return string.data(using: .utf8)
        @unknown default:
            return nil
        }
    }
}
