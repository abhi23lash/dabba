import Foundation

extension Notification.Name {
    /// Page ▸ Next / Previous (⌘↓ / ⌘↑): move through a mode's suggestions.
    static let nextMethod = Notification.Name("dabba.nextMethod")
    static let previousMethod = Notification.Name("dabba.previousMethod")
    /// Page ▸ Commands (⌘K): the same list as typing `/`.
    static let showCommands = Notification.Name("dabba.showCommands")
}

/// A method is one mental model (Catch, First principles, Inversion,
/// Second-order). It can be called in any mode, and changes the page by
/// adding a step. In the UI it's only ever called by its plain name.
enum MethodID: String, Codable, CaseIterable, Identifiable {
    case catchAll        // `catch` is a Swift keyword
    case firstPrinciples
    case inversion
    case secondOrder
    case fiveWs
    case circleOfCompetence
    case twoTrack
    case decisionTree
    case punchCard

    var id: Self { self }
    var method: Method { Method.all[self]! }
}

struct Method {
    let id: MethodID
    let name: String
    let hint: String
    /// Grey text in the empty writing space: what this model is and how to
    /// use it. It disappears as soon as you type.
    let explanation: String

    static let all: [MethodID: Method] = [
        .catchAll: Method(id: .catchAll, name: "Catch",
                          hint: "Get it all down. Park side ideas, don't chase them.",
                          explanation: "Get the whole idea down as it comes. Messy is fine. When a side idea shows up, park it with ⌘] instead of chasing it."),
        .firstPrinciples: Method(id: .firstPrinciples, name: "First principles",
                                 hint: "Underneath the details, what is this? One sentence.",
                                 explanation: "Say what this is underneath the details, in one plain sentence. Not right yet? Cross it out and try again below."),
        .inversion: Method(id: .inversion, name: "Inversion",
                           hint: "A year from now, this failed. Why?",
                           explanation: "Picture it a year from now, and it failed. Write down why, one reason per line."),
        .secondOrder: Method(id: .secondOrder, name: "Second-order",
                             hint: "If it works, and then what?",
                             explanation: "Say it works. What happens next, and what happens after that? Follow the effects one step at a time."),
        .fiveWs: Method(id: .fiveWs, name: "Five W's",
                        hint: "Who, what, where, when, why?",
                        explanation: "Pin it down with one line each: who it's for, what it is, where and when it happens, and why it matters."),
        .circleOfCompetence: Method(id: .circleOfCompetence, name: "Circle of competence",
                                    hint: "What do you actually know here?",
                                    explanation: "Split what you know firsthand from what you're guessing. Two lists: I know… and I'm guessing…"),
        .twoTrack: Method(id: .twoTrack, name: "Two-track",
                          hint: "The reasons you'd give, and what's really pulling you.",
                          explanation: "First the reasons you'd give someone else. Then what's really pulling you, the part you wouldn't say out loud."),
        .decisionTree: Method(id: .decisionTree, name: "Decision tree",
                              hint: "Branch each option into what could happen.",
                              explanation: "Write an option and press Return, then list what could happen under it. Return on an empty line for the next option. Add a rough chance like 30%."),
        .punchCard: Method(id: .punchCard, name: "Punch card",
                           hint: "If you only got 20 of these, would this be one?",
                           explanation: "Imagine you get only 20 choices like this in your whole life. Would you spend one on this? Say why or why not."),
    ]
}

/// A mode bundles a suggested sequence of methods, a landing stem and a
/// default mark. Following the sequence is guided, never enforced.
enum ModeID: String, Codable, CaseIterable, Identifiable {
    case open
    case ideas

    var id: Self { self }
    var mode: Mode { self == .ideas ? .ideas : .open }
}

struct Mode {
    let id: ModeID
    let name: String
    let suggested: [MethodID]
    let optional: [MethodID]
    let landingStem: String

    static let open = Mode(id: .open, name: "Open", suggested: [.catchAll],
                           optional: [], landingStem: "")
    static let ideas = Mode(id: .ideas, name: "Ideas",
                            suggested: [.catchAll, .firstPrinciples, .inversion, .secondOrder],
                            optional: [.secondOrder],
                            landingStem: "The idea is…")
}
