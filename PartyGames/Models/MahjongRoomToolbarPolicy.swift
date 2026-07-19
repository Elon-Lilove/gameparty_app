enum MahjongRoomToolbarItem: CaseIterable, Hashable {
    case invite
    case transferOwner
    case voice
    case table

    var title: String {
        switch self {
        case .invite:
            "玩家邀请"
        case .transferOwner:
            "房主转让"
        case .voice:
            "语音播放"
        case .table:
            "台板（茶水）"
        }
    }
}

enum MahjongRoomToolbarPolicy {
    static func items(isOwner: Bool, isMultiplayer: Bool) -> [MahjongRoomToolbarItem] {
        isOwner && isMultiplayer ? [.invite, .transferOwner, .voice, .table] : [.invite, .voice, .table]
    }
}
