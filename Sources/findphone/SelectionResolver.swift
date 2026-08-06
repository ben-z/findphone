import Foundation

enum CandidateSelectionOutcome: Equatable {
    case quit
    case selectedIdentity(String)
    case invalid
}

struct CandidateSelectionResolver {
    static func resolve(rawInput: String, candidates: [Advertiser]) -> CandidateSelectionOutcome {
        let value = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased() == "q" {
            return .quit
        }

        guard
            let selected = Int(value),
            selected > 0,
            selected <= candidates.count
        else {
            return .invalid
        }

        return .selectedIdentity(candidates[selected - 1].identity)
    }
}
