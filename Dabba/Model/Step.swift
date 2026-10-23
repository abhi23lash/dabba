import Foundation
import SwiftData

/// One model applied during a session. Its heading sits inline in
/// `Session.text`, where it was called, and the writing under the heading
/// belongs to it, so every model shares the one page (strike instead of
/// delete, tangent notes, commands). `lines` is for models that later need
/// structured lines.
@Model
final class Step {
    var id: UUID = UUID()
    var order: Int = 0
    var methodID: String = MethodID.catchAll.rawValue
    /// Text the method was called on; empty means the whole session.
    var input: String = ""
    /// Where the step's heading sits in the session's text, in UTF-16 units.
    var anchor: Int = 0
    /// Where the step's box closes (its closing line break); -1 while open.
    var endAnchor: Int = -1
    var lines: [StepLine] = []
    var session: Session?

    init(order: Int, method: MethodID, input: String = "") {
        self.order = order
        self.methodID = method.rawValue
        self.input = input
    }

    var method: MethodID { MethodID(rawValue: methodID) ?? .catchAll }

    /// The step's writing as one block, for models whose own page isn't
    /// built yet. Stored as the first `.body` line.
    var body: String {
        get { lines.first { $0.role == .body }?.text ?? "" }
        set {
            if let index = lines.firstIndex(where: { $0.role == .body }) {
                lines[index].text = newValue
            } else {
                lines.insert(StepLine(text: newValue, role: .body), at: 0)
            }
        }
    }

    /// A step with nothing written in it. Catch is never empty in this sense:
    /// its text lives on the session.
    var isEmpty: Bool {
        method != .catchAll && lines.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

struct StepLine: Codable, Hashable, Identifiable {
    enum Role: String, Codable { case body, attempt, reason, condition, consequence }

    var id = UUID()
    var text: String = ""
    var role: Role = .body
    var isStruck = false
    /// A condition points at the reason it flips.
    var parentID: UUID?
}
