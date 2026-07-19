import Foundation

enum MahjongSettlementValidationError: LocalizedError, Equatable, Sendable {
    case invalidMultiplier

    var errorDescription: String? {
        "倍率请输入大于 0 且不超过 1000000 的数字"
    }
}

enum MahjongSettlementValidation {
    static func parse(_ raw: String) -> Result<Double, MahjongSettlementValidationError> {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let value = Double(normalized),
              value.isFinite,
              value > 0,
              value <= 1_000_000 else {
            return .failure(.invalidMultiplier)
        }
        return .success(value)
    }
}
