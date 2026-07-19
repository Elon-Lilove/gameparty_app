import Foundation
import Observation

@MainActor
@Observable
final class MahjongScoreViewModel {
    var displayName = "我"
    var roomTitle = "麻将计分"
    var playerNames = ["玩家1"]
    var session: MahjongRoomSession?
    var snapshot: MahjongRoomSnapshot?
    var unfinishedRooms: [MahjongRoomInfo] = []
    var recentTableSnapshot: MahjongRoomSnapshot?
    var isInviteVisible = false
    var inviteURL: URL?
    var isSettlementVisible = false
    var settlementMultiplier = "1"
    var isScoreDetailVisible = false
    var voiceBroadcastEnabled = false {
        didSet {
            if voiceBroadcastEnabled {
                voiceAnnouncer.prime(with: snapshot)
            }
        }
    }
    var tableServiceEnabled = false
    var isLoading = false
    var isSettling = false
    var errorMessage: String?
    var roomFeedbackMessage: String?
    var connectionMessage = "未连接"

    private let service: MahjongScoreService
    private let realtimeClient: MahjongRealtimeClient
    private let deviceId: String
    private let voiceAnnouncer = MahjongVoiceAnnouncer()
    private var snapshotPollingTask: Task<Void, Never>?
    private var operationTimeoutTask: Task<Void, Never>?
    private var feedbackDismissTask: Task<Void, Never>?
    private var isRealtimeConnected = false
    private var roomActionState = MahjongRoomActionState()

    init(
        service: MahjongScoreService = .shared,
        realtimeClient: MahjongRealtimeClient = MahjongRealtimeClient(),
        deviceId: String = MahjongDeviceStore.deviceId()
    ) {
        self.service = service
        self.realtimeClient = realtimeClient
        self.deviceId = deviceId
    }

    var canAddPlayer: Bool {
        playerNames.count < MahjongRoomDraft.maxPlayers
    }

    var canRemovePlayer: Bool {
        playerNames.count > 2
    }

    var currentDeviceId: String {
        deviceId
    }

    var hasEndedRoom: Bool {
        snapshot?.room.status == "ended"
    }

    var isOwner: Bool {
        snapshot?.room.ownerDeviceId == deviceId
    }

    var pendingRoomAction: MahjongRoomPendingAction? {
        roomActionState.pending
    }

    var canMutateRoom: Bool {
        guard !isSettling,
              snapshot?.room.status == "active",
              roomActionState.pending == nil else { return false }
        return session?.isLocal == true || isRealtimeConnected
    }

    func isGivingScore(to playerId: String) -> Bool {
        guard case .giveScore(let targetPlayerId, _) = roomActionState.pending else { return false }
        return targetPlayerId == playerId
    }

    var isTableScorePending: Bool {
        guard case .tableScore = roomActionState.pending else { return false }
        return true
    }

    var unfinishedBannerText: String? {
        nil
    }

    var hasRecentTable: Bool {
        recentTableSnapshot != nil
    }

    func addPlayer() {
        guard canAddPlayer else { return }
        playerNames.append("玩家\(playerNames.count + 1)")
    }

    func removePlayer(at offsets: IndexSet) {
        guard canRemovePlayer else { return }
        playerNames.remove(atOffsets: offsets)
        if playerNames.count < 2 {
            playerNames = ["玩家1", "玩家2"]
        }
    }

    func loadUnfinishedRooms() async {
        await loadRecentTable()
    }

    func loadRecentTable() async {
        do {
            unfinishedRooms = try await service.loadUnfinishedRooms(deviceId: deviceId).rooms
                .filter { !MahjongHiddenRoomsStore.contains($0.code) }
        } catch {
            if unfinishedRooms.isEmpty {
                errorMessage = Self.friendlyNetworkError(error)
            }
        }

        guard let room = unfinishedRooms.first(where: { $0.status == "active" }) ?? unfinishedRooms.first else {
            recentTableSnapshot = nil
            return
        }

        do {
            recentTableSnapshot = try await service.loadRoom(code: room.code)
        } catch {
            recentTableSnapshot = nil
        }
    }

    func dismissRecentTable() {
        guard let code = recentTableSnapshot?.room.code else { return }
        MahjongHiddenRoomsStore.hide(code)
        unfinishedRooms.removeAll { $0.code == code }
        recentTableSnapshot = nil
    }

    func endRecentTable() async {
        guard let room = recentTableSnapshot?.room else { return }

        if room.code == "本地" {
            endLocalRecentTable()
            return
        }

        await runNetworkAction {
            let request = MahjongJoinRoomRequest(
                deviceId: deviceId,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "我" : displayName
            )
            let joinResponse = try await service.joinRoom(code: room.code, request: request)
            let multiplier = room.multiplier > 0 ? room.multiplier : 1
            if room.status == "active" {
                _ = try await service.settleRoom(
                    code: room.code,
                    memberToken: joinResponse.memberToken,
                    multiplier: multiplier
                )
            }
        }
        await loadRecentTable()
    }

    func deleteRecentTable() async {
        guard let room = recentTableSnapshot?.room else { return }

        guard MahjongRecentTablePolicy.shouldEndRemotely(
            code: room.code,
            status: room.status,
            isOwner: room.ownerDeviceId == deviceId
        ) else {
            dismissRecentTable()
            return
        }

        await runNetworkAction {
            let request = MahjongJoinRoomRequest(
                deviceId: deviceId,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "我" : displayName
            )
            let joinResponse = try await service.joinRoom(code: room.code, request: request)
            try await service.dismissRoom(code: room.code, memberToken: joinResponse.memberToken)
            MahjongHiddenRoomsStore.hide(room.code)
            recentTableSnapshot = nil
            unfinishedRooms.removeAll { $0.code == room.code }
        }
        await loadRecentTable()
    }

    private func endLocalRecentTable() {
        guard var snapshot = recentTableSnapshot, snapshot.room.status == "active" else {
            Task { await loadRecentTable() }
            return
        }

        let multiplier = snapshot.room.multiplier > 0 ? snapshot.room.multiplier : 1
        let scores = snapshot.players.map(\.score)
        let maxScore = scores.max() ?? 0
        let minScore = scores.min() ?? 0
        for index in snapshot.players.indices {
            let score = snapshot.players[index].score
            snapshot.players[index].multiplierScore = Double(score) * multiplier
            if maxScore == minScore {
                snapshot.players[index].result = "draw"
            } else if score == maxScore {
                snapshot.players[index].result = "win"
            } else if score == minScore {
                snapshot.players[index].result = "lose"
            } else {
                snapshot.players[index].result = "draw"
            }
        }
        snapshot.room.status = "ended"
        snapshot.room.multiplier = multiplier
        snapshot.room.endedAt = Self.timestamp()
        snapshot.room.updatedAt = snapshot.room.endedAt ?? Self.timestamp()
        recentTableSnapshot = snapshot
    }

    func openRecentTable() async {
        guard let room = recentTableSnapshot?.room else {
            await resumeFirstUnfinishedRoom()
            return
        }

        if session?.roomCode == room.code, snapshot != nil {
            return
        }

        if room.mode == .solo, session?.isLocal == true, session?.roomCode == room.code {
            return
        }

        await runNetworkAction {
            let request = MahjongJoinRoomRequest(
                deviceId: deviceId,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "我" : displayName
            )
            let response = try await service.joinRoom(code: room.code, request: request)
            apply(response: response)
        }
    }

    func createRoom(mode: MahjongRoomMode) async {
        if mode == .solo {
            createLocalSoloRoom()
            return
        }

        await runNetworkAction {
            try await createMultiplayerRoomThrowing()
            isInviteVisible = true
        }
    }

    /// 多人建房（可抛错），供加载页重试使用。
    func createMultiplayerRoomThrowing() async throws {
        errorMessage = nil
        let draft = MahjongRoomDraft(
            deviceId: deviceId,
            displayName: displayName,
            title: roomTitle,
            mode: .multiplayer,
            playerNames: playerNames
        )
        let request = draft.createRoomRequest()
        let response = try await service.createRoom(request)
        apply(response: response)
        isInviteVisible = true
    }

    func resumeFirstUnfinishedRoom() async {
        guard let room = unfinishedRooms.first else { return }
        await runNetworkAction {
            let request = MahjongJoinRoomRequest(
                deviceId: deviceId,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "我" : displayName
            )
            let response = try await service.joinRoom(code: room.code, request: request)
            apply(response: response)
        }
    }

    func adjustScore(playerId: String, delta: Int) async {
        if session?.isLocal == true {
            applyOptimisticScore(playerId: playerId, delta: delta)
            return
        }

        await performRealtimeAction(
            action: { .adjustScore(playerId: playerId, operationId: $0) },
            send: { operationId in
                try await realtimeClient.sendAdjustScore(playerId: playerId, delta: delta, operationId: operationId)
            }
        )
    }

    func rename(playerId: String, name: String) async {
        if session?.isLocal == true {
            renameLocalPlayer(playerId: playerId, name: name)
            return
        }

        await performRealtimeAction(
            action: { .rename(playerId: playerId, operationId: $0) },
            send: { operationId in
                try await realtimeClient.sendRenamePlayer(playerId: playerId, name: name, operationId: operationId)
            }
        )
    }

    func addRoomPlayer() async {
        if session?.isLocal == true {
            addLocalPlayer()
            return
        }

        let nextIndex = (snapshot?.players.count ?? 0) + 1
        await performRealtimeAction(
            action: { .addPlayer(operationId: $0) },
            send: { operationId in
                try await realtimeClient.sendAddPlayer(name: "玩家\(nextIndex)", operationId: operationId)
            }
        )
    }

    func transferOwner(to deviceId: String) async {
        await performRealtimeAction(
            action: { .transferOwner(targetDeviceId: deviceId, operationId: $0) },
            send: { operationId in
                try await realtimeClient.sendTransferOwner(targetDeviceId: deviceId, operationId: operationId)
            }
        )
    }

    func removePlayer(playerId: String) async {
        await performRealtimeAction(
            action: { .removePlayer(playerId: playerId, operationId: $0) },
            send: { operationId in
                try await realtimeClient.sendRemovePlayer(playerId: playerId, operationId: operationId)
            }
        )
    }

    func leaveCurrentPlayer() async {
        if session?.isLocal == true {
            leaveRoom()
            return
        }

        guard let player = snapshot?.players.first(where: { $0.deviceId == deviceId }) else {
            leaveRoom()
            return
        }

        await performRealtimeAction(
            action: { .removePlayer(playerId: player.id, operationId: $0) },
            send: { operationId in
                try await realtimeClient.sendRemovePlayer(playerId: player.id, operationId: operationId)
            }
        )
    }

    func giveTableScore(amount: Int) async {
        if session?.isLocal == true {
            giveLocalTableScore(amount: amount)
            return
        }

        await performRealtimeAction(
            action: { .tableScore(operationId: $0) },
            send: { operationId in
                try await realtimeClient.sendTableScore(amount: amount, operationId: operationId)
            }
        )
    }

    func reopenInvite() {
        guard session?.isLocal != true else { return }
        isInviteVisible = true
    }

    func giveScore(to targetPlayerId: String, amount: Int) async {
        guard (1...1_000_000).contains(amount) else {
            errorMessage = "给分请输入 1 到 1000000 的整数"
            return
        }
        if session?.isLocal == true {
            giveLocalScore(to: targetPlayerId, amount: amount)
            return
        }

        await performRealtimeAction(
            action: { .giveScore(targetPlayerId: targetPlayerId, operationId: $0) },
            send: { operationId in
                try await realtimeClient.sendGiveScore(
                    targetPlayerId: targetPlayerId,
                    amount: amount,
                    operationId: operationId
                )
            }
        )
    }

    func settleRoom() async {
        guard !isSettling,
              roomActionState.pending == nil else { return }
        guard snapshot?.room.status == "active" else {
            errorMessage = "房间已经结算"
            return
        }
        guard let session else { return }
        feedbackDismissTask?.cancel()
        feedbackDismissTask = nil
        let multiplier: Double
        switch MahjongSettlementValidation.parse(settlementMultiplier) {
        case .success(let value):
            multiplier = value
        case .failure(let error):
            errorMessage = error.localizedDescription
            isSettlementVisible = true
            return
        }

        if session.isLocal {
            settleLocalRoom(multiplier: multiplier)
            return
        }

        guard isOwner else {
            errorMessage = "只有房主可以结算房间"
            return
        }

        isSettling = true
        errorMessage = nil
        defer { isSettling = false }

        do {
            let response = try await service.settleRoom(
                code: session.roomCode,
                memberToken: session.memberToken,
                multiplier: multiplier
            )
            snapshot = response.snapshot
            isSettlementVisible = false
            isScoreDetailVisible = true
            unfinishedRooms.removeAll { $0.code == session.roomCode }
            recentTableSnapshot = nil
            roomFeedbackMessage = "结算成功"
            await loadRecentTable()
        } catch {
            errorMessage = Self.friendlyNetworkError(error)
            isSettlementVisible = true
        }
    }

    func leaveRoom() {
        stopSnapshotPolling()
        operationTimeoutTask?.cancel()
        operationTimeoutTask = nil
        feedbackDismissTask?.cancel()
        feedbackDismissTask = nil
        roomActionState.cancel()
        isRealtimeConnected = false
        realtimeClient.disconnect()
        session = nil
        snapshot = nil
        inviteURL = nil
        isInviteVisible = false
        isSettlementVisible = false
        isScoreDetailVisible = false
        isSettling = false
        roomFeedbackMessage = nil
        connectionMessage = "未连接"
        Task { await loadRecentTable() }
    }

    private func performRealtimeAction(
        action: (String) -> MahjongRoomPendingAction,
        send: (String) async throws -> Void
    ) async {
        guard isRealtimeConnected else {
            errorMessage = "实时同步正在连接，请稍后再试"
            return
        }

        let operationId = UUID().uuidString
        guard roomActionState.begin(action(operationId)) else {
            errorMessage = "上一项操作仍在处理中"
            return
        }

        operationTimeoutTask?.cancel()
        feedbackDismissTask?.cancel()
        errorMessage = nil
        roomFeedbackMessage = roomActionState.pending?.progressText

        do {
            try await send(operationId)
            startOperationTimeout(operationId: operationId)
        } catch {
            roomActionState.fail(operationId: operationId)
            roomFeedbackMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func startOperationTimeout(operationId: String) {
        operationTimeoutTask?.cancel()
        operationTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self else { return }
            guard self.roomActionState.fail(operationId: operationId) else { return }
            self.roomFeedbackMessage = nil
            self.errorMessage = "操作未确认，请检查网络后重试"
        }
    }

    private func completeRealtimeAction(_ acknowledgement: MahjongRealtimeAcknowledgement?) {
        guard let acknowledgement, acknowledgement.actorDeviceId == deviceId else { return }
        guard roomActionState.complete(operationId: acknowledgement.operationId) else { return }
        operationTimeoutTask?.cancel()
        operationTimeoutTask = nil
        feedbackDismissTask?.cancel()
        roomFeedbackMessage = "操作成功"
        feedbackDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.roomFeedbackMessage = nil
            self?.feedbackDismissTask = nil
        }
    }

    private func failRealtimeAction(
        _ acknowledgement: MahjongRealtimeAcknowledgement?,
        message: String
    ) {
        guard let acknowledgement, acknowledgement.actorDeviceId == deviceId else { return }
        guard roomActionState.fail(operationId: acknowledgement.operationId) else { return }
        operationTimeoutTask?.cancel()
        operationTimeoutTask = nil
        roomFeedbackMessage = nil
        errorMessage = message
    }

    private func runNetworkAction(_ action: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil

        do {
            try await action()
        } catch {
            errorMessage = Self.friendlyNetworkError(error)
        }

        isLoading = false
    }

    static func friendlyNetworkError(_ error: Error) -> String {
        if let serviceError = error as? MahjongScoreServiceError {
            if case .server(let message) = serviceError {
                return friendlyRealtimeError(message)
            }
            return serviceError.localizedDescription
        }
        if error is DecodingError {
            return "服务器数据格式异常，请更新后重试"
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate:
                return "安全连接失败：当前网络无法访问服务器，请切换网络或关闭代理后重试"
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "网络不可用，请检查网络后重试"
            case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
                return "服务器连接超时，请切换 Wi-Fi/蜂窝或关闭代理后重试"
            default:
                break
            }
        }
        if nsError.domain == NSCocoaErrorDomain {
            return "服务器数据格式异常，请更新后重试"
        }
        return error.localizedDescription
    }

    private static func friendlyRealtimeError(_ message: String) -> String {
        if message.localizedCaseInsensitiveContains("balance must be zero") {
            return "该玩家分数需先结清为 0，才能移出房间"
        }
        if message.localizedCaseInsensitiveContains("membership was removed")
            || message.localizedCaseInsensitiveContains("membership is no longer active") {
            return "你已被移出房间"
        }
        if message.localizedCaseInsensitiveContains("only the room owner") {
            return "只有房主可以执行此操作"
        }
        if message.localizedCaseInsensitiveContains("room is not active") {
            return "房间已经结算，不能继续操作"
        }
        if message.localizedCaseInsensitiveContains("member token") {
            return "房间身份已失效，请重新创建或加入房间"
        }
        return message
    }

    private func apply(response: MahjongRoomResponse) {
        MahjongMemberTokenStore.save(response.memberToken, for: response.snapshot.room.code)
        let nextSession = MahjongRoomSession(
            roomCode: response.snapshot.room.code,
            memberToken: response.memberToken,
            isLocal: false
        )
        session = nextSession
        snapshot = response.snapshot
        voiceAnnouncer.prime(with: response.snapshot)
        inviteURL = try? service.inviteURL(roomCode: response.snapshot.room.code)
        settlementMultiplier = String(format: "%.0f", response.snapshot.room.multiplier)
        connectRealtime(session: nextSession)
    }

    private func createLocalSoloRoom() {
        let now = Self.timestamp()
        let localPlayerNames: [String] = {
            if playerNames.count >= 2 {
                return Array(playerNames.prefix(MahjongRoomDraft.maxPlayers))
            }
            return ["玩家1", "玩家2", "玩家3", "玩家4"]
        }()
        let players = localPlayerNames.enumerated().map { index, rawName in
            MahjongScorePlayer(
                id: UUID().uuidString,
                name: rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "玩家\(index + 1)" : rawName,
                deviceId: index == 0 ? deviceId : nil,
                seat: nil,
                score: 0,
                multiplierScore: 0,
                result: nil,
                sortOrder: index,
                isActive: true
            )
        }
        let room = MahjongRoomInfo(
            id: UUID().uuidString,
            code: "本地",
            title: roomTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "麻将计分" : roomTitle,
            status: "active",
            mode: .solo,
            startingScore: 0,
            ownerDeviceId: deviceId,
            multiplier: 1,
            createdAt: now,
            endedAt: nil,
            updatedAt: now
        )
        session = MahjongRoomSession(roomCode: room.code, memberToken: "", isLocal: true)
        snapshot = MahjongRoomSnapshot(room: room, players: players, recentEvents: [])
        inviteURL = nil
        isInviteVisible = false
        connectionMessage = "本地计分"
    }

    private func addLocalPlayer() {
        guard var snapshot, snapshot.room.status == "active", snapshot.players.count < MahjongRoomDraft.maxPlayers else { return }
        let nextIndex = snapshot.players.count
        snapshot.players.append(
            MahjongScorePlayer(
                id: UUID().uuidString,
                name: "玩家\(nextIndex + 1)",
                deviceId: nil,
                seat: nil,
                score: 0,
                multiplierScore: 0,
                result: nil,
                sortOrder: nextIndex,
                isActive: true
            )
        )
        snapshot.room.updatedAt = Self.timestamp()
        self.snapshot = snapshot
    }

    private func renameLocalPlayer(playerId: String, name: String) {
        guard var snapshot, let index = snapshot.players.firstIndex(where: { $0.id == playerId }) else { return }
        let nextName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextName.isEmpty else { return }
        snapshot.players[index].name = String(nextName.prefix(24))
        snapshot.room.updatedAt = Self.timestamp()
        self.snapshot = snapshot
    }

    private func applyOptimisticScore(playerId: String, delta: Int) {
        guard var snapshot, snapshot.room.status == "active" else { return }
        guard let index = snapshot.players.firstIndex(where: { $0.id == playerId }) else { return }

        snapshot.players[index].score += delta
        self.snapshot = snapshot
    }

    private func applyOptimisticGiveScore(to targetPlayerId: String, amount: Int) {
        guard var snapshot, snapshot.room.status == "active" else { return }
        guard let sourceIndex = snapshot.players.firstIndex(where: { $0.deviceId == deviceId }) else { return }
        guard let targetIndex = snapshot.players.firstIndex(where: { $0.id == targetPlayerId }) else { return }
        guard sourceIndex != targetIndex else { return }

        snapshot.players[sourceIndex].score -= amount
        snapshot.players[targetIndex].score += amount
        self.snapshot = snapshot
    }

    private func giveLocalScore(to targetPlayerId: String, amount: Int) {
        guard amount > 0 else { return }
        applyOptimisticGiveScore(to: targetPlayerId, amount: amount)
        appendLocalScoreEvents(targetPlayerId: targetPlayerId, amount: amount, reason: "给分")
    }

    private func giveLocalTableScore(amount: Int) {
        guard amount > 0, var snapshot, snapshot.room.status == "active" else { return }
        if snapshot.players.firstIndex(where: { $0.seat == "table" || $0.name == "台板" }) == nil {
            snapshot.players.append(
                MahjongScorePlayer(
                    id: UUID().uuidString,
                    name: "台板",
                    deviceId: nil,
                    seat: "table",
                    score: 0,
                    multiplierScore: 0,
                    result: nil,
                    sortOrder: snapshot.players.count,
                    isActive: true
                )
            )
            self.snapshot = snapshot
        }
        guard let tableId = self.snapshot?.players.first(where: { $0.seat == "table" || $0.name == "台板" })?.id else { return }
        giveLocalScore(to: tableId, amount: amount)
    }

    private func appendLocalScoreEvents(targetPlayerId: String, amount: Int, reason: String) {
        guard var snapshot else { return }
        guard let sourceIndex = snapshot.players.firstIndex(where: { $0.deviceId == deviceId }) else { return }
        guard let targetIndex = snapshot.players.firstIndex(where: { $0.id == targetPlayerId }) else { return }
        let now = Self.timestamp()
        let source = snapshot.players[sourceIndex]
        let target = snapshot.players[targetIndex]
        snapshot.recentEvents.insert(
            MahjongScoreEvent(
                id: UUID().uuidString,
                playerId: source.id,
                actorMemberId: deviceId,
                delta: -amount,
                reason: reason,
                scoreAfter: source.score,
                createdAt: now
            ),
            at: 0
        )
        snapshot.recentEvents.insert(
            MahjongScoreEvent(
                id: UUID().uuidString,
                playerId: target.id,
                actorMemberId: deviceId,
                delta: amount,
                reason: reason,
                scoreAfter: target.score,
                createdAt: now
            ),
            at: 0
        )
        snapshot.room.updatedAt = now
        self.snapshot = snapshot
    }

    private func settleLocalRoom(multiplier: Double) {
        guard var snapshot, snapshot.room.status == "active" else { return }
        isSettling = true
        let scores = snapshot.players.map(\.score)
        let maxScore = scores.max() ?? 0
        let minScore = scores.min() ?? 0
        for index in snapshot.players.indices {
            let score = snapshot.players[index].score
            snapshot.players[index].multiplierScore = Double(score) * multiplier
            if maxScore == minScore {
                snapshot.players[index].result = "draw"
            } else if score == maxScore {
                snapshot.players[index].result = "win"
            } else if score == minScore {
                snapshot.players[index].result = "lose"
            } else {
                snapshot.players[index].result = "draw"
            }
        }
        snapshot.room.status = "ended"
        snapshot.room.multiplier = multiplier
        snapshot.room.endedAt = Self.timestamp()
        snapshot.room.updatedAt = snapshot.room.endedAt ?? Self.timestamp()
        self.snapshot = snapshot
        isSettlementVisible = false
        isScoreDetailVisible = true
        isSettling = false
    }

    private func connectRealtime(session: MahjongRoomSession) {
        guard !session.isLocal else { return }
        isRealtimeConnected = false
        startSnapshotPolling(roomCode: session.roomCode)
        do {
            let url = try service.webSocketURL(roomCode: session.roomCode, memberToken: session.memberToken)
            connectionMessage = "连接中"
            realtimeClient.connect(
                url: url,
                onSnapshot: { [weak self] snapshot, acknowledgement in
                    Task { @MainActor in
                        self?.receiveRealtimeSnapshot(snapshot, acknowledgement: acknowledgement)
                    }
                },
                onStatus: { [weak self] state in
                    Task { @MainActor in
                        switch state {
                        case .connecting:
                            self?.connectionMessage = "连接中"
                        case .connected:
                            self?.isRealtimeConnected = true
                            self?.connectionMessage = "实时同步中"
                            self?.errorMessage = nil
                        case .reconnecting:
                            self?.isRealtimeConnected = false
                            self?.connectionMessage = "同步中（轮询）"
                        }
                    }
                },
                onError: { [weak self] message, acknowledgement in
                    Task { @MainActor in
                        self?.failRealtimeAction(acknowledgement, message: Self.friendlyRealtimeError(message))
                        if acknowledgement == nil {
                            self?.isRealtimeConnected = false
                            self?.connectionMessage = "同步中（轮询）"
                        }
                    }
                }
            )
        } catch {
            isRealtimeConnected = false
            connectionMessage = "同步中（轮询）"
        }
    }

    private func startSnapshotPolling(roomCode: String) {
        stopSnapshotPolling()
        snapshotPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                guard self.session?.roomCode == roomCode, self.session?.isLocal != true else { return }
                // WebSocket 正常时不轮询，避免每几秒整表刷新造成卡顿。
                if self.isRealtimeConnected { continue }
                do {
                    let latest = try await self.service.loadRoom(code: roomCode)
                    if self.snapshot != latest {
                        self.receiveRealtimeSnapshot(latest, acknowledgement: nil)
                        self.connectionMessage = "同步中（轮询）"
                    }
                } catch {
                    // 轮询失败时保留现有快照，等待下一次。
                }
            }
        }
    }

    private func stopSnapshotPolling() {
        snapshotPollingTask?.cancel()
        snapshotPollingTask = nil
    }

    private func receiveRealtimeSnapshot(
        _ nextSnapshot: MahjongRoomSnapshot,
        acknowledgement: MahjongRealtimeAcknowledgement?
    ) {
        guard nextSnapshot.players.contains(where: { $0.deviceId == deviceId }) else {
            if let roomCode = session?.roomCode {
                MahjongMemberTokenStore.remove(for: roomCode)
            }
            errorMessage = "你已退出房间"
            leaveRoom()
            return
        }

        snapshot = nextSnapshot
        completeRealtimeAction(acknowledgement)
        voiceAnnouncer.announceNewEvents(in: nextSnapshot, enabled: voiceBroadcastEnabled)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}

enum MahjongDeviceStore {
    private static let key = "party-games-mahjong-device-id"

    static func deviceId() -> String {
        if let id = UserDefaults.standard.string(forKey: key), !id.isEmpty {
            return id
        }

        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}

enum MahjongHiddenRoomsStore {
    private static let key = "party-games-mahjong-hidden-rooms"

    static func contains(_ code: String) -> Bool {
        hiddenCodes().contains(code.uppercased())
    }

    static func hide(_ code: String) {
        var codes = hiddenCodes()
        codes.insert(code.uppercased())
        UserDefaults.standard.set(Array(codes), forKey: key)
    }

    private static func hiddenCodes() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
}
