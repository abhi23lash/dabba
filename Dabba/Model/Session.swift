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
    var landing: String = ""

    init(createdAt: Date = .now) {
        self.createdAt = createdAt
    }

    var isFinished: Bool { finishedAt != nil }
}
