import Foundation

@main
struct MahjongRoomToolbarPolicyTest {
    static func main() {
        precondition(MahjongRoomToolbarPolicy.items(isOwner: true, isMultiplayer: true) == [.invite, .transferOwner, .voice, .table])
        precondition(MahjongRoomToolbarPolicy.items(isOwner: false, isMultiplayer: true) == [.invite, .voice, .table])
        precondition(MahjongRoomToolbarPolicy.items(isOwner: true, isMultiplayer: false) == [.invite, .voice, .table])
        precondition(MahjongRoomToolbarItem.invite.title == "玩家邀请")
        precondition(MahjongRoomToolbarItem.transferOwner.title == "房主转让")
        precondition(MahjongRoomToolbarItem.voice.title == "语音播放")
        precondition(MahjongRoomToolbarItem.table.title == "台板（茶水）")
    }
}
