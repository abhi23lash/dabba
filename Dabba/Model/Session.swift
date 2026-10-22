import Foundation
import SwiftData

/// One sitting on the page: an opening question, free writing, and a landing.
/// A session with no `finishedAt` is the live draft; there is at most one.
///
/// Every stored property has a default so the model stays compatible with
/// CloudKit sync when it is added later.
@Model
final class Session {
    var createdAt: Date = Date.now
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

    init(createdAt: Date = .now) {
        self.createdAt = createdAt
    }

    var isFinished: Bool { finishedAt != nil }
}
