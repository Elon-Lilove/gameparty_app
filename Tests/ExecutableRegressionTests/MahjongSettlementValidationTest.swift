import Foundation

@main
enum MahjongSettlementValidationTest {
    static func main() throws {
        let integerMultiplier = try MahjongSettlementValidation.parse("2").get()
        let decimalMultiplier = try MahjongSettlementValidation.parse(" 1.5 ").get()
        precondition(integerMultiplier == 2)
        precondition(decimalMultiplier == 1.5)
        precondition(isRejected(""))
        precondition(isRejected("0"))
        precondition(isRejected("-1"))
        precondition(isRejected("1000001"))
        precondition(isRejected("abc"))
    }

    private static func isRejected(_ raw: String) -> Bool {
        switch MahjongSettlementValidation.parse(raw) {
        case .success:
            return false
        case .failure:
            return true
        }
    }
}
