import Foundation
import SwiftData

/// One sitting on the page: an opening question, free writing, and a landing.
/// A session with no `finishedAt` is the live draft; there is at most one.
///
/// Every stored property has a default so the model stays compatible with
/// CloudKit sync when it is added later.
@Model
final class Session {
    /// Stable identity, written into the session's Markdown file header.
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    /// When this session was last the current page. The current page is the
    /// unfinished session opened most recently.
    var lastOpenedAt: Date = Date.now
    /// The session's Markdown file name in the user's files folder, so a
    /// renamed question renames the file instead of making a new one.
    var fileName: String = ""
    var finishedAt: Date?
    var question: String = ""
    var text: String = ""
    /// Struck-through parts of `text`, flat as [location, length, ...] in
    /// UTF-16 units. Struck words stay on the page instead of being deleted.
    var struck: [Int] = []
    /// Side thoughts branched off the writing, shown as notes beside the page.
    @Relationship(deleteRule: .cascade, inverse: \Tangent.session)
    var tangents: [Tangent]? = []
    var landing: String = ""

    // MARK: Modes

    /// `ModeID` raw value. Open is today's page; Ideas walks through steps.
    var modeID: String = ModeID.open.rawValue
    @Relationship(deleteRule: .cascade, inverse: \Step.session)
    var steps: [Step]? = []
    /// `order` of the step being worked on.
    var currentStepOrder: Int = 0

    var mode: Mode { (ModeID(rawValue: modeID) ?? .open).mode }
    var orderedSteps: [Step] { (steps ?? []).sorted { $0.order < $1.order } }
    var currentStep: Step? { orderedSteps.first { $0.order == currentStepOrder } }

    init(createdAt: Date = .now) {
        self.createdAt = createdAt
    }

    var isFinished: Bool { finishedAt != nil }

    /// Has anything been written yet? An empty page can simply be reused.
    var hasWriting: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
