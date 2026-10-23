import Foundation

/// Everything reachable from the page: `/` lists modes (`/ideas`), `@` lists
/// models (`@inversion`), and ⌘K lists both.
struct Command: Identifiable, Hashable {
    enum Kind: Hashable {
        case mode(ModeID)
        case method(MethodID)
        case later          // listed so people know it's coming, not selectable yet
    }

    let id: String          // what you type: "ideas", "first principles"
    let detail: String
    let aliases: [String]
    let kind: Kind

    var isAvailable: Bool { kind != .later }
    var isMode: Bool {
        switch kind {
        case .mode, .later: return true
        case .method: return false
        }
    }

    static let all: [Command] = [
        Command(id: "ideas", detail: "Develop an idea", aliases: ["i", "idea"], kind: .mode(.ideas)),
        Command(id: "stuck", detail: "Find your next step", aliases: ["s"], kind: .later),
        Command(id: "deciding", detail: "Make a choice", aliases: ["d", "decide"], kind: .later),
        Command(id: "open", detail: "A plain page", aliases: ["o"], kind: .mode(.open)),
        Command(id: "first principles", detail: MethodID.firstPrinciples.method.hint,
                aliases: ["fp"], kind: .method(.firstPrinciples)),
        Command(id: "inversion", detail: MethodID.inversion.method.hint,
                aliases: ["inv"], kind: .method(.inversion)),
        Command(id: "second-order", detail: MethodID.secondOrder.method.hint,
                aliases: ["so", "second order", "and then"], kind: .method(.secondOrder)),
        Command(id: "five w's", detail: MethodID.fiveWs.method.hint,
                aliases: ["5w", "w", "five ws", "5 ws", "fivews"], kind: .method(.fiveWs)),
        Command(id: "circle of competence", detail: MethodID.circleOfCompetence.method.hint,
                aliases: ["coc", "circle", "competence"], kind: .method(.circleOfCompetence)),
        Command(id: "two-track", detail: MethodID.twoTrack.method.hint,
                aliases: ["tt", "two track"], kind: .method(.twoTrack)),
        Command(id: "decision tree", detail: MethodID.decisionTree.method.hint,
                aliases: ["dt", "tree"], kind: .method(.decisionTree)),
        Command(id: "punch card", detail: MethodID.punchCard.method.hint,
                aliases: ["pc", "punch", "20"], kind: .method(.punchCard)),
    ]

    /// Exact aliases first, then names that start with the query, then
    /// anything whose letters appear in order (so "inv", "fpr" still match).
    static func matching(_ query: String) -> [Command] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        func score(_ c: Command) -> Int? {
            if c.aliases.contains(q) || c.id == q { return 0 }
            if c.id.hasPrefix(q) || c.aliases.contains(where: { $0.hasPrefix(q) }) { return 1 }
            var rest = Substring(q)
            for ch in c.id where ch == rest.first { rest = rest.dropFirst() }
            return rest.isEmpty ? 2 : nil
        }
        return all.compactMap { c in score(c).map { (c, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}
