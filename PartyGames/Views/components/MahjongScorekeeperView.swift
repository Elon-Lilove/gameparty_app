import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct MahjongScorekeeperView: View {
    @State private var viewModel = MahjongScoreViewModel()
    @State private var renamePlayer: MahjongScorePlayer?
    @State private var renameText = ""
    @State private var giveTargetPlayer: MahjongScorePlayer?
    @State private var giveAmountText = "1"
    @State private var isRecentScoreDetailVisible = false
    @State private var isEndRecentTableAlertVisible = false
    @State private var isDeleteRecentTableAlertVisible = false
    @State private var isConnectingPresented = false
    @State private var didCopyInviteLink = false

    private var isRoomPresented: Binding<Bool> {
        Binding(
            get: { viewModel.snapshot != nil && !isConnectingPresented },
            set: { isPresented in
                if !isPresented {
                    viewModel.leaveRoom()
                }
            }
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            entryContent
                .padding(.horizontal, DesignTokens.pageHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .creamBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isConnectingPresented) {
            MahjongConnectingView(viewModel: viewModel) {
                isConnectingPresented = false
            }
        }
        .navigationDestination(isPresented: isRoomPresented) {
            if let snapshot = viewModel.snapshot {
                roomContent(snapshot: snapshot)
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            await viewModel.loadRecentTable()
        }
        .onChange(of: viewModel.snapshot) { _, snapshot in
            guard snapshot == nil else { return }
            Task { await viewModel.loadRecentTable() }
        }
        .sheet(isPresented: $isRecentScoreDetailVisible) {
            if let snapshot = viewModel.recentTableSnapshot {
                scoreDetail(snapshot: snapshot)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $viewModel.isInviteVisible) {
            inviteSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.isScoreDetailVisible) {
            if let snapshot = viewModel.snapshot {
                scoreDetail(snapshot: snapshot)
                    .presentationDetents([.medium, .large])
            }
        }
        .alert("输入倍率，快速结算！", isPresented: $viewModel.isSettlementVisible) {
            TextField("1", text: $viewModel.settlementMultiplier)
                .keyboardType(.decimalPad)
            Button("取消", role: .cancel) {}
            Button("确定") {
                HapticService.medium()
                Task { await viewModel.settleRoom() }
            }
        }
        .alert("修改名字", isPresented: renameBinding) {
            TextField("名字", text: $renameText)
            Button("取消", role: .cancel) {
                renamePlayer = nil
            }
            Button("确定") {
                guard let player = renamePlayer else { return }
                Task { await viewModel.rename(playerId: player.id, name: renameText) }
                renamePlayer = nil
            }
        }
        .alert("输入给分", isPresented: giveBinding) {
            TextField("1", text: $giveAmountText)
                .keyboardType(.numberPad)
            Button("取消", role: .cancel) {
                giveTargetPlayer = nil
                giveAmountText = "1"
            }
            Button("确定") {
                guard let player = giveTargetPlayer else { return }
                let amount = Int(giveAmountText.trimmingCharacters(in: .whitespacesAndNewlines))
                guard let amount, (1...1_000_000).contains(amount) else {
                    viewModel.errorMessage = "给分请输入 1 到 1000000 的整数"
                    return
                }
                if player.seat == "table" || player.name == "台板" {
                    Task { await viewModel.giveTableScore(amount: amount) }
                } else {
                    Task { await viewModel.giveScore(to: player.id, amount: amount) }
                }
                giveTargetPlayer = nil
                giveAmountText = "1"
            }
        }
        .alert("确定要结束本次记分？", isPresented: $isEndRecentTableAlertVisible) {
            Button("在玩一会", role: .cancel) {}
            Button("确定结束") {
                Task { await viewModel.endRecentTable() }
            }
        }
        .alert("删除后不可恢复，确定要删除本局记录？", isPresented: $isDeleteRecentTableAlertVisible) {
            Button("不了", role: .cancel) {}
            Button("确定删除", role: .destructive) {
                Task { await viewModel.deleteRecentTable() }
            }
        }
        .animation(.snappy(duration: 0.22), value: viewModel.snapshot?.room.code)
    }

    private var entryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 10) {
                startButton(
                    title: "开始记分-多人模式",
                    subtitle: "所有玩家自己操作计分",
                    systemName: "person.3.fill",
                    mode: .multiplayer
                )
                startButton(
                    title: "开始记分-单人模式",
                    subtitle: "房主给所有玩家按局计分",
                    systemName: "person.crop.circle.badge.checkmark",
                    mode: .solo
                )
            }

            if viewModel.hasRecentTable, let snapshot = viewModel.recentTableSnapshot {
                recentTableSection(snapshot: snapshot)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(DesignTokens.bodyFont(size: 12, weight: .semibold))
                    .foregroundStyle(.pink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentTableSection(snapshot: MahjongRoomSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0.18, green: 0.74, blue: 0.42))
                    .frame(width: 4, height: 18)
                Text("最近一桌")
                    .font(DesignTokens.titleFont(size: 18))
                    .foregroundStyle(DesignTokens.stone900)
            }
            .padding(.top, 4)

            recentTableCard(snapshot: snapshot)
        }
    }

    private func recentTableCard(snapshot: MahjongRoomSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(recentTableModeTitle(snapshot.room.mode))
                    .font(DesignTokens.bodyFont(size: 14, weight: .semibold))
                    .foregroundStyle(DesignTokens.stone500)

                Text(recentTableStatusText(snapshot.room.status))
                    .font(DesignTokens.bodyFont(size: 14, weight: .bold))
                    .foregroundStyle(recentTableStatusColor(snapshot.room.status))

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    recentTableActionButton(systemName: "chart.xyaxis.line") {
                        isRecentScoreDetailVisible = true
                    }
                    if snapshot.room.ownerDeviceId == viewModel.currentDeviceId,
                       snapshot.room.status == "active" {
                        recentTableActionButton(systemName: "xmark") {
                            isEndRecentTableAlertVisible = true
                        }
                    }
                    recentTableActionButton(systemName: "trash") {
                        isDeleteRecentTableAlertVisible = true
                    }
                }
            }

            Button {
                if snapshot.room.status == "ended" {
                    isRecentScoreDetailVisible = true
                } else {
                    Task { await viewModel.openRecentTable() }
                }
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 18) {
                        ForEach(recentTablePlayers(snapshot)) { player in
                            recentTablePlayerItem(
                                player: player,
                                roomStatus: snapshot.room.status,
                                isOwner: player.deviceId == snapshot.room.ownerDeviceId
                            )
                        }
                        Spacer(minLength: 0)
                    }

                    Text(recentTableFooter(snapshot))
                        .font(DesignTokens.bodyFont(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.stone400)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.hapticPlain)
            .disabled(viewModel.isLoading)
        }
        .padding(14)
        .background(DesignTokens.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignTokens.borderSubtle, lineWidth: 1)
        }
    }

    private func recentTableActionButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignTokens.stone500)
                }
            }
            .frame(width: 34, height: 34)
            .background(DesignTokens.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignTokens.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.hapticPlain)
        .disabled(viewModel.isLoading)
    }

    private func recentTablePlayerItem(
        player: MahjongScorePlayer,
        roomStatus: String,
        isOwner: Bool
    ) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                recentTableAvatar(for: player)
                if isOwner {
                    Text("桌主")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .offset(x: 8, y: -6)
                }
            }

            Text(player.name)
                .font(DesignTokens.bodyFont(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.stone900)
                .lineLimit(1)

            Text(recentTableScoreText(player, roomStatus: roomStatus))
                .font(DesignTokens.titleFont(size: 24))
                .foregroundStyle(player.score > 0 ? Color.red : DesignTokens.stone900)
        }
        .frame(minWidth: 56)
    }

    private func recentTableAvatar(for player: MahjongScorePlayer) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.inverseSurface)
            Text(String(player.name.prefix(1)))
                .font(DesignTokens.titleFont(size: 18))
                .foregroundStyle(DesignTokens.inverseText)
        }
        .frame(width: 44, height: 44)
    }

    private func recentTablePlayers(_ snapshot: MahjongRoomSnapshot) -> [MahjongScorePlayer] {
        snapshot.players
            .filter { $0.isActive && $0.seat != "table" && $0.name != "台板" }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func recentTableModeTitle(_ mode: MahjongRoomMode) -> String {
        switch mode {
        case .multiplayer:
            return "多人计分桌"
        case .solo:
            return "单人计分桌"
        }
    }

    private func recentTableStatusText(_ status: String) -> String {
        status == "ended" ? "已结束" : "进行中"
    }

    private func recentTableStatusColor(_ status: String) -> Color {
        status == "ended" ? DesignTokens.stone400 : Color(red: 0.18, green: 0.74, blue: 0.42)
    }

    private func recentTableFooter(_ snapshot: MahjongRoomSnapshot) -> String {
        guard let startedAt = MahjongRecentTableFormatter.parseDate(snapshot.room.createdAt) else {
            return ""
        }

        let startLabel = MahjongRecentTableFormatter.formatStart(startedAt)
        if snapshot.room.status == "ended",
           let endedAt = snapshot.room.endedAt,
           let endedDate = MahjongRecentTableFormatter.parseDate(endedAt) {
            let minutes = max(0, Int(endedDate.timeIntervalSince(startedAt) / 60))
            return "\(startLabel) 开始 | 共进行\(minutes)分钟"
        }

        let minutes = max(0, Int(Date().timeIntervalSince(startedAt) / 60))
        return "\(startLabel) 开始 | 已进行\(minutes)分钟"
    }

    private func recentTableScoreText(_ player: MahjongScorePlayer, roomStatus: String) -> String {
        if roomStatus == "ended" {
            let value = player.multiplierScore
            if value == floor(value) {
                return String(format: "%.0f", value)
            }
            return String(format: "%.1f", value)
        }
        return "\(player.score)"
    }

    private func startButton(title: String, subtitle: String, systemName: String, mode: MahjongRoomMode) -> some View {
        Button {
            if mode == .multiplayer {
                // 先跳转加载页，再联网，避免入口页干等像卡死。
                isConnectingPresented = true
            } else {
                Task { await viewModel.createRoom(mode: mode) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DesignTokens.inverseText)
                    .frame(width: 42, height: 42)
                    .background(DesignTokens.inverseSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(DesignTokens.bodyFont(size: 15, weight: .bold))
                        .foregroundStyle(DesignTokens.stone900)
                    Text(subtitle)
                        .font(DesignTokens.bodyFont(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.stone500)
                }

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(DesignTokens.stone400)
                }
            }
            .padding(12)
            .background(DesignTokens.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignTokens.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.hapticPlain)
        .disabled(viewModel.isLoading)
    }

    private func roomContent(snapshot: MahjongRoomSnapshot) -> some View {
        VStack(spacing: 0) {
            roomStatusBar
            roomToolbar(snapshot)
            playerTable(snapshot)
            Spacer(minLength: 0)
            bottomBar(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.surfaceElevatedSoft.opacity(0.6))
        .creamBackground()
    }

    private var roomStatusBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.canMutateRoom ? "dot.radiowaves.left.and.right" : "arrow.trianglehead.2.clockwise.rotate.90")
                Text(viewModel.connectionMessage)
                Spacer()
                if let pending = viewModel.pendingRoomAction {
                    ProgressView()
                        .controlSize(.small)
                    Text(pending.progressText)
                } else if let feedback = viewModel.roomFeedbackMessage {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(feedback)
                }
            }
            .font(DesignTokens.bodyFont(size: 12, weight: .semibold))
            .foregroundStyle(DesignTokens.stone600)

            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        viewModel.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭错误提示")
                }
                .font(DesignTokens.bodyFont(size: 12, weight: .semibold))
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesignTokens.surfaceElevatedSoft)
    }

    private func roomToolbar(_ snapshot: MahjongRoomSnapshot) -> some View {
        HStack(spacing: 4) {
            ForEach(
                MahjongRoomToolbarPolicy.items(isOwner: viewModel.isOwner, isMultiplayer: snapshot.room.mode == .multiplayer),
                id: \.self
            ) { item in
                roomToolbarItem(item, snapshot: snapshot)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(DesignTokens.surfaceElevated)
    }

    @ViewBuilder
    private func roomToolbarItem(_ item: MahjongRoomToolbarItem, snapshot: MahjongRoomSnapshot) -> some View {
        switch item {
        case .invite:
            RoomGlassButton {
                if snapshot.room.mode == .multiplayer {
                    didCopyInviteLink = false
                    viewModel.reopenInvite()
                } else {
                    Task { await viewModel.addRoomPlayer() }
                }
            } label: {
                compactToolbarLabel(title: "玩家邀请", systemName: "person.badge.plus")
            }
            .disabled(snapshot.room.mode == .solo && !viewModel.canMutateRoom)
        case .transferOwner:
            transferMenu(snapshot)
        case .voice:
            RoomGlassButton(prominent: viewModel.voiceBroadcastEnabled) {
                viewModel.voiceBroadcastEnabled.toggle()
            } label: {
                compactToolbarLabel(title: "语音播放", systemName: "speaker.wave.2.fill")
            }
        case .table:
            RoomGlassButton(prominent: viewModel.tableServiceEnabled) {
                viewModel.tableServiceEnabled.toggle()
            } label: {
                compactToolbarLabel(title: "台板（茶水）", systemName: "cup.and.saucer.fill")
            }
        }
    }

    private func compactToolbarLabel(title: String, systemName: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(DesignTokens.bodyFont(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func transferMenu(_ snapshot: MahjongRoomSnapshot) -> some View {
        let candidates = snapshot.players.filter {
            $0.isActive
                && ($0.deviceId ?? "") != viewModel.currentDeviceId
                && $0.deviceId != nil
                && $0.seat != "table"
                && $0.name != "台板"
        }

        return Menu {
            if candidates.isEmpty {
                Text("暂无可转让玩家")
            }
            ForEach(candidates) { player in
                Button(player.name) {
                    if let deviceId = player.deviceId {
                        Task { await viewModel.transferOwner(to: deviceId) }
                    }
                }
            }
        } label: {
            compactToolbarLabel(title: "房主转让", systemName: "person.crop.circle.badge.arrow.forward")
        }
        .buttonStyle(.glass)
        .disabled(!viewModel.canMutateRoom || candidates.isEmpty)
        .frame(maxWidth: .infinity)
    }

    private func playerTable(_ snapshot: MahjongRoomSnapshot) -> some View {
        let players = displayedPlayers(snapshot)

        return VStack(spacing: 0) {
            HStack {
                Text("玩家")
                Spacer()
                Text("得分")
                    .frame(width: 88)
                Text("操作")
                    .frame(width: 92)
            }
            .font(DesignTokens.bodyFont(size: 15, weight: .bold))
            .foregroundStyle(DesignTokens.stone600)
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(DesignTokens.surfaceElevated)

            Text(snapshot.room.status == "ended" ? "对局已结算" : "祝大家生活愉快！")
                .font(DesignTokens.bodyFont(size: 15, weight: .bold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(DesignTokens.surfaceElevatedSoft)

            List {
                ForEach(players) { player in
                    playerRow(player, snapshot: snapshot)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            playerSwipeActions(player, snapshot: snapshot)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(CGFloat(players.count) * 68, 420))
        }
    }

    private func displayedPlayers(_ snapshot: MahjongRoomSnapshot) -> [MahjongScorePlayer] {
        var players = snapshot.players.filter(\.isActive)
        let hasTable = players.contains { $0.seat == "table" || $0.name == "台板" }
        if viewModel.tableServiceEnabled && snapshot.room.status == "active" && !hasTable {
            players.append(
                MahjongScorePlayer(
                    id: "__table_service__",
                    name: "台板",
                    deviceId: nil,
                    seat: "table",
                    score: 0,
                    multiplierScore: 0,
                    result: nil,
                    sortOrder: (players.map(\.sortOrder).max() ?? -1) + 1,
                    isActive: true
                )
            )
        }
        return players.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func playerRow(_ player: MahjongScorePlayer, snapshot: MahjongRoomSnapshot) -> some View {
        let isSelf = player.deviceId == viewModel.currentDeviceId
        let isRoomOwner = player.deviceId == snapshot.room.ownerDeviceId
        let isTable = player.name == "台板" || player.seat == "table"
        let removalBlockedByBalance =
            viewModel.isOwner && !isSelf && !isRoomOwner && !isTable && player.deviceId != nil && player.score != 0
        return HStack(spacing: 10) {
            Button {
                if isSelf || viewModel.isOwner {
                    renameText = player.name
                    renamePlayer = player
                }
            } label: {
                HStack(spacing: 10) {
                    avatar(for: player)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(player.name)
                                .lineLimit(1)
                            if isSelf {
                                Text("自己")
                                    .font(DesignTokens.bodyFont(size: 10, weight: .bold))
                                    .foregroundStyle(DesignTokens.inverseText)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            if isRoomOwner {
                                Text("房主")
                                    .font(DesignTokens.bodyFont(size: 10, weight: .bold))
                                    .foregroundStyle(DesignTokens.inverseText)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(DesignTokens.inverseSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                        }
                        Text(player.seat ?? "玩家")
                            .font(DesignTokens.bodyFont(size: 11, weight: .semibold))
                            .foregroundStyle(DesignTokens.stone500)
                    }
                }
            }
            .font(DesignTokens.bodyFont(size: 15, weight: .bold))
            .foregroundStyle(DesignTokens.stone900)
            .buttonStyle(.hapticPlain)
            .disabled(!(isSelf || viewModel.isOwner) || !viewModel.canMutateRoom)

            Spacer()

            Text(displayScore(player, roomStatus: snapshot.room.status))
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(snapshot.room.status == "ended" ? .red : DesignTokens.stone900)
                .monospacedDigit()
                .frame(width: 88)

            VStack(spacing: 2) {
                giveButton(player: player, disabled: !canGiveScore(to: player, snapshot: snapshot))
                if removalBlockedByBalance && snapshot.room.status == "active" {
                    Text("归零后可移除")
                        .font(DesignTokens.bodyFont(size: 9, weight: .semibold))
                        .foregroundStyle(DesignTokens.stone500)
                }
            }
            .frame(width: 92)
        }
        .padding(.horizontal, 12)
        .frame(height: 68)
        .background(isSelf ? DesignTokens.surfaceInset : DesignTokens.surfaceElevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.borderSubtle)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func playerSwipeActions(_ player: MahjongScorePlayer, snapshot: MahjongRoomSnapshot) -> some View {
        let isSelf = player.deviceId == viewModel.currentDeviceId
        let isRoomOwner = player.deviceId == snapshot.room.ownerDeviceId
        let isTable = player.name == "台板" || player.seat == "table"

        if viewModel.isOwner && !isSelf && !isRoomOwner && !isTable {
            Button(role: .destructive) {
                Task { await viewModel.removePlayer(playerId: player.id) }
            } label: {
                Label("踢出", systemImage: "person.crop.circle.badge.xmark")
            }
            .disabled(!viewModel.canMutateRoom || player.score != 0)
        }

        if isSelf && !viewModel.isOwner {
            Button(role: .destructive) {
                Task { await viewModel.leaveCurrentPlayer() }
            } label: {
                Label("退出", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .disabled(!viewModel.canMutateRoom || player.score != 0)
        }
    }

    private func avatar(for player: MahjongScorePlayer) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.inverseSurface)
            Text(String(player.name.prefix(1)))
                .font(DesignTokens.titleFont(size: 18))
                .foregroundStyle(DesignTokens.inverseText)
        }
        .frame(width: 44, height: 44)
    }

    private func giveButton(player: MahjongScorePlayer, disabled: Bool) -> some View {
        RoomGlassButton(prominent: true) {
            giveAmountText = "1"
            giveTargetPlayer = player
        } label: {
            HStack(spacing: 5) {
                if viewModel.isGivingScore(to: player.id) {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(viewModel.isGivingScore(to: player.id) ? "提交" : "给分")
            }
            .font(DesignTokens.bodyFont(size: 14, weight: .bold))
            .frame(width: 72, height: 36)
        }
        .disabled(disabled || !viewModel.canMutateRoom)
        .opacity((disabled || !viewModel.canMutateRoom) ? 0.35 : 1)
    }

    private func bottomBar(_ snapshot: MahjongRoomSnapshot) -> some View {
        HStack(spacing: 12) {
            RoomGlassButton {
                viewModel.isScoreDetailVisible = true
            } label: {
                Text("给分详情")
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .font(DesignTokens.bodyFont(size: 17, weight: .bold))

            RoomGlassButton(prominent: true) {
                viewModel.isSettlementVisible = true
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSettling {
                        ProgressView()
                    }
                    Text(viewModel.isSettling ? "结算中..." : (snapshot.room.status == "ended" ? "已结算" : "结算房间"))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .font(DesignTokens.bodyFont(size: 17, weight: .bold))
            .disabled(
                !viewModel.isOwner
                    || snapshot.room.status == "ended"
                    || viewModel.isSettling
                    || viewModel.pendingRoomAction != nil
            )
        }
        .padding(12)
        .background(DesignTokens.surfaceElevated)
    }

    private var inviteSheet: some View {
        VStack(spacing: 14) {
            Text("扫码加入房间")
                .font(DesignTokens.titleFont(size: 22))
                .foregroundStyle(DesignTokens.stone900)

            if let inviteURL = viewModel.inviteURL {
                QRCodeView(url: inviteURL)
                    .frame(width: 240, height: 240)
                Text("系统相机 / 微信均可扫码打开网页")
                    .font(DesignTokens.bodyFont(size: 15, weight: .bold))
                    .foregroundStyle(DesignTokens.stone600)
                    .multilineTextAlignment(.center)
                RoomGlassButton {
                    UIPasteboard.general.string = inviteURL.absoluteString
                    didCopyInviteLink = true
                } label: {
                    Label(didCopyInviteLink ? "网页链接已复制" : inviteURL.absoluteString, systemImage: didCopyInviteLink ? "checkmark" : "link")
                        .font(DesignTokens.bodyFont(size: 11, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }

            RoomGlassButton(prominent: true) {
                viewModel.isInviteVisible = false
            } label: {
                Text("进入房间")
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .font(DesignTokens.bodyFont(size: 15, weight: .bold))
        }
        .padding(20)
    }

    private func scoreDetail(snapshot: MahjongRoomSnapshot) -> some View {
        VStack(spacing: 0) {
            Text(snapshot.room.status == "ended" ? "计分器" : "给分详情")
                .font(DesignTokens.titleFont(size: 22))
                .foregroundStyle(DesignTokens.stone900)
                .padding(.vertical, 18)

            HStack {
                Text("玩家")
                Spacer()
                Text(snapshot.room.status == "ended" ? "胜负" : "当前")
                    .frame(width: 70)
                Text("得分")
                    .frame(width: 70)
                Text("倍率分")
                    .frame(width: 70)
            }
            .font(DesignTokens.bodyFont(size: 14, weight: .bold))
            .foregroundStyle(DesignTokens.stone500)
            .padding(.horizontal, 16)
            .frame(height: 44)

            ForEach(snapshot.players.sorted { $0.sortOrder < $1.sortOrder }) { player in
                HStack(spacing: 10) {
                    Text("\(player.sortOrder + 1)")
                        .font(DesignTokens.bodyFont(size: 14, weight: .bold))
                        .foregroundStyle(DesignTokens.inverseSurface)
                        .frame(width: 28)
                    avatar(for: player)
                    Text(player.name)
                        .font(DesignTokens.bodyFont(size: 15, weight: .bold))
                        .foregroundStyle(DesignTokens.stone900)
                    Spacer()
                    Text(resultText(player.result))
                        .foregroundStyle(.red)
                        .frame(width: 70)
                    Text("\(player.score)")
                        .foregroundStyle(.red)
                        .frame(width: 70)
                    Text(formatDouble(player.multiplierScore))
                        .foregroundStyle(.red)
                        .frame(width: 70)
                }
                .font(DesignTokens.bodyFont(size: 15, weight: .bold))
                .padding(.horizontal, 16)
                .frame(height: 70)
                .background(player.sortOrder == 0 ? DesignTokens.surfaceInset : DesignTokens.surfaceElevated)
            }

            if !snapshot.recentEvents.isEmpty {
                Divider()
                    .padding(.top, 8)
                List(snapshot.recentEvents.prefix(20)) { event in
                    let playerName = snapshot.players.first(where: { $0.id == event.playerId })?.name ?? "玩家"
                    HStack {
                        Text(playerName)
                        Spacer()
                        Text(event.delta > 0 ? "+\(event.delta)" : "\(event.delta)")
                        Text("→ \(event.scoreAfter)")
                    }
                    .font(DesignTokens.bodyFont(size: 13, weight: .semibold))
                }
                .listStyle(.plain)
            }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamePlayer != nil },
            set: { if !$0 { renamePlayer = nil } }
        )
    }

    private var giveBinding: Binding<Bool> {
        Binding(
            get: { giveTargetPlayer != nil },
            set: { if !$0 { giveTargetPlayer = nil } }
        )
    }

    private func canGiveScore(to player: MahjongScorePlayer, snapshot: MahjongRoomSnapshot) -> Bool {
        guard snapshot.room.status == "active" else { return false }
        if player.name == "台板" || player.seat == "table" {
            return viewModel.tableServiceEnabled
                && snapshot.players.contains { $0.deviceId == viewModel.currentDeviceId }
        }
        if player.deviceId == viewModel.currentDeviceId {
            return false
        }
        return snapshot.players.contains { $0.deviceId == viewModel.currentDeviceId }
    }

    private func displayScore(_ player: MahjongScorePlayer, roomStatus: String) -> String {
        roomStatus == "ended" ? formatDouble(player.multiplierScore) : "\(player.score)"
    }

    private func resultText(_ result: String?) -> String {
        switch result {
        case "win":
            return "胜利"
        case "lose":
            return "失败"
        case "draw":
            return "平局"
        default:
            return "-"
        }
    }

    private func formatDouble(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}

private struct QRCodeView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 120))
                    .foregroundStyle(DesignTokens.stone400)
            }
        }
        .accessibilityLabel("房间邀请二维码")
        .accessibilityValue(url.absoluteString)
        .task(id: url.absoluteString) {
            image = Self.makeQRCode(from: url.absoluteString)
        }
    }

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// 生成可被系统相机与微信同时识别的标准 QR（HTTPS 明文 URL）。
    private static func makeQRCode(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        // H：更高容错，屏幕反光/轻微遮挡时仍易识别。
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }

        // 放大模块像素，避免插值发糊。
        let scale: CGFloat = 12
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // 额外白边静区，提升相机对焦与微信识别稳定性。
        let quietZone: CGFloat = 4 * scale
        let expanded = scaled.transformed(by: CGAffineTransform(
            translationX: quietZone,
            y: quietZone
        ))
        let canvas = expanded.extent.insetBy(dx: -quietZone, dy: -quietZone)
        let withQuietZone = expanded.composited(over: CIImage(color: .white).cropped(to: canvas))

        guard let cgImage = context.createCGImage(withQuietZone, from: canvas) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
