import Foundation

/// Result rank by share of correct answers. All thresholds live here so they are easy to tune.
enum ResultRank: String, CaseIterable {
    case s, a, b, c

    /// S 90%+ (9/10, 18/20), A 75%+, B 50%+, C below. A perfect run is always S.
    static let thresholds: [(ResultRank, Double)] = [(.s, 0.9), (.a, 0.75), (.b, 0.5)]

    static func rank(correct: Int, total: Int) -> ResultRank {
        guard total > 0 else { return .c }
        let share = Double(correct) / Double(total)
        return thresholds.first { share >= $0.1 }?.0 ?? .c
    }

    var imageName: String { "rank_\(rawValue)" }
    var letter: String { rawValue.uppercased() }
}
