import Foundation
import SwiftData

/// A side thought branched off the main writing. It lives as a sticky note in
/// the column beside the page; a small number mark stays in the main text.
/// One level only for now: tangents don't branch.
///
/// Every stored property has a default, to stay CloudKit-compatible.
@Model
final class Tangent {
    var id: UUID = UUID()
    /// Shown as a superscript mark (¹, ²…) in the main text and on the note.
    var number: Int = 0
    var text: String = ""
    /// Where the mark sits in the session's text, in UTF-16 units. Kept up to
    /// date as the main text is edited.
    var anchor: Int = 0
    var createdAt: Date = Date.now
    var session: Session?

    init(number: Int, text: String, anchor: Int) {
        self.number = number
        self.text = text
        self.anchor = anchor
    }

    /// The mark as it appears in the main text.
    var mark: String { Self.mark(for: number) }

    static func mark(for number: Int) -> String {
        let digits: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
        return String(String(number).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }
}
