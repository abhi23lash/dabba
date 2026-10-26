import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Strike instead of delete.
///
/// Backspace on a single character works normally, for typos. Removing a
/// selection doesn't delete it: the text stays on the page, struck through and
/// faded, so abandoned thoughts remain visible. Typing over a selection strikes
/// the old words and puts the new ones right after them.
enum Strike {
    static var baseAttributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = Paper.pageLineSpacing
        return [.font: Paper.Platform.page,
                .foregroundColor: Paper.Platform.ink,
                .paragraphStyle: style]
    }

    /// Added on top of whatever is there, so tangent marks keep their link.
    static var struckAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: Paper.Platform.inkMuted,
         .strikethroughStyle: NSUnderlineStyle.single.rawValue,
         .strikethroughColor: Paper.Platform.inkMuted]
    }

    /// The page as saved: plain text plus struck ranges, stored flat as
    /// [location, length, location, length, ...] in UTF-16 units.
    static func attributed(text: String, struck: [Int]) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes)
        for range in ranges(from: struck, length: result.length) {
            result.addAttributes(struckAttributes, range: range)
        }
        return result
    }

    static func ranges(from flat: [Int], length: Int) -> [NSRange] {
        stride(from: 0, to: flat.count - 1, by: 2).compactMap { i in
            let range = NSRange(location: flat[i], length: flat[i + 1])
            let valid = range.location >= 0 && range.length > 0 && NSMaxRange(range) <= length
            return valid ? range : nil
        }
    }

    static func flatRanges(in text: NSAttributedString) -> [Int] {
        var flat: [Int] = []
        text.enumerateAttribute(.strikethroughStyle,
                                in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let style = value as? Int, style != 0 { flat += [range.location, range.length] }
        }
        return flat
    }

    /// True when every visible character in `range` is already struck through.
    /// Line breaks don't count, so a struck multi-line selection still qualifies.
    static func isStruck(_ range: NSRange, in text: NSAttributedString) -> Bool {
        let string = text.string as NSString
        var struck = true
        text.enumerateAttribute(.strikethroughStyle, in: range) { value, run, stop in
            let isOn = ((value as? Int) ?? 0) != 0
            let onlyBreaks = string.substring(with: run).allSatisfy { $0 == "\n" }
            if !isOn && !onlyBreaks { struck = false; stop.pointee = true }
        }
        return struck
    }

    /// Applies a strike when an edit replaces the whole current selection.
    /// Returns the new caret position, or nil to let the edit happen normally.
    static func apply(to storage: NSTextStorage, edit range: NSRange,
                      selection: NSRange, replacement: String) -> NSRange? {
        guard selection.length > 0, NSEqualRanges(range, selection) else { return nil }
        // Deleting text that's already struck removes it for good: the way to
        // clear something you really don't want on the page (a bad paste).
        if replacement.isEmpty, isStruck(selection, in: storage) { return nil }

        storage.beginEditing()
        storage.addAttributes(struckAttributes, range: selection)
        var caret = NSMaxRange(selection)
        // Keep a space between the struck words and whatever comes next.
        let text = storage.string as NSString
        let lastStruck = text.substring(with: NSRange(location: caret - 1, length: 1))
        let next = caret < text.length ? text.substring(with: NSRange(location: caret, length: 1)) : ""
        let endsInWord = !lastStruck.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let followedBySpace = next == " " || next == "\n"
        let startsWithSpace = replacement.hasPrefix(" ") || replacement.hasPrefix("\n")
        let needsSpace = endsInWord && !followedBySpace && !startsWithSpace
        let insert = (needsSpace ? " " : "") + replacement
        if !insert.isEmpty {
            storage.insert(NSAttributedString(string: insert, attributes: baseAttributes), at: caret)
            caret += (insert as NSString).length
        }
        storage.endEditing()
        return NSRange(location: caret, length: 0)
    }
}

// MARK: - Tangent marks

extension NSAttributedString.Key {
    /// Marks the superscript number that stands in for a tangent.
    static let tangentID = NSAttributedString.Key("dabba.tangentID")
}

/// The small numbered marks that stand where a tangent branched off.
enum TangentMarks {
    static let scheme = "dabba-tangent"

    static func attributes(for id: UUID) -> [NSAttributedString.Key: Any] {
        var attributes = Strike.baseAttributes
        attributes[.tangentID] = id.uuidString
        attributes[.link] = URL(string: "\(scheme):\(id.uuidString)")!
        attributes[.font] = PlatformFont.systemFont(ofSize: 15, weight: .semibold)
        return attributes
    }

    /// Puts saved marks back on the page. A mark only returns if its text is
    /// still where the tangent says it is.
    static func apply(_ tangents: [TangentAnchor], to text: NSMutableAttributedString) {
        let string = text.string as NSString
        for tangent in tangents {
            let range = NSRange(location: tangent.anchor, length: (tangent.mark as NSString).length)
            guard NSMaxRange(range) <= string.length, string.substring(with: range) == tangent.mark
            else { continue }
            text.addAttributes(attributes(for: tangent.id), range: range)
        }
    }

    /// Where each mark sits now, in UTF-16 units.
    static func anchors(in text: NSAttributedString) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        text.enumerateAttribute(.tangentID, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let raw = value as? String, let id = UUID(uuidString: raw) { result[id] = range.location }
        }
        return result
    }

    static func id(from link: Any) -> UUID? {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        guard let url, url.scheme == scheme else { return nil }
        return UUID(uuidString: url.absoluteString.replacingOccurrences(of: "\(scheme):", with: ""))
    }
}

/// What the text view needs to know about a tangent to draw its mark.
struct TangentAnchor: Equatable {
    let id: UUID
    let mark: String
    let anchor: Int
}

/// What the page asks of the text view, and hears back from it.
struct TangentHooks {
    var saved: [TangentAnchor] = []
    /// Called on ⌘] with the selected text and where it was. Returns the new
    /// tangent's id and mark.
    var branch: (String, Int) -> (UUID, String) = { _, _ in (UUID(), "") }
    var open: (UUID) -> Void = { _ in }
    /// Mark positions in the text, to keep tangents' anchors current.
    var moved: ([UUID: Int]) -> Void = { _ in }
    /// Mark positions on screen (y, from the top of the writing area).
    var onScreen: ([UUID: CGFloat]) -> Void = { _ in }
    /// Asks the text view to take a removed note's mark out of the writing.
    var remove: TangentRemoval?
}

struct TangentRemoval: Equatable {
    let token: Int
    let id: UUID
}

extension TangentMarks {
    /// Takes a tangent's mark out of the text. False if it wasn't there.
    @discardableResult
    static func removeMark(_ id: UUID, from storage: NSTextStorage) -> Bool {
        var found: NSRange?
        storage.enumerateAttribute(.tangentID, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if (value as? String) == id.uuidString { found = range; stop.pointee = true }
        }
        guard let range = found else { return false }
        storage.deleteCharacters(in: range)
        return true
    }
}

// MARK: - Slash commands

enum CommandKey { case up, down, enter }

/// Which list the command card shows: `/` modes, `@` models, ⌘K both.
enum CommandScope {
    case modes, models, all

    init?(trigger: String) {
        switch trigger {
        case "/": self = .modes
        case "@": self = .models
        default: return nil
        }
    }
}

/// `/` or `@` at the start of a line opens the command card. The text view
/// reports the typed query and cursor position; the page owns the card.
struct CommandHooks {
    /// The text after the trigger, which list, and the cursor's rect in the
    /// writing area; a nil query closes the card.
    var query: (String?, CommandScope, CGRect) -> Void = { _, _, _ in }
    /// Arrow keys and Return while the card is open. True if the card used it.
    var key: (CommandKey) -> Bool = { _ in false }
    /// Bumped by the page when a command ran by click, to remove the `/text`.
    var consumeRequest = 0

    /// `/` and `@` open the card at the start of a line or after a space or
    /// tab, so "I think @inv" works but "and/or" and "a@b.com" stay plain.
    static func startsLine(_ text: NSString, at location: Int) -> Bool {
        guard location > 0 else { return true }
        let before = text.character(at: location - 1)
        return before == 10 || before == 32 || before == 9   // "\n", " ", "\t"
    }

    /// The query typed since the trigger at `start`, or nil if abandoned.
    static func query(in text: NSString, start: Int, caret: Int) -> String? {
        guard start < text.length, caret > start,
              [47, 64].contains(text.character(at: start)) else { return nil }  // "/" "@"
        let query = text.substring(with: NSRange(location: start + 1, length: caret - start - 1))
        if query.contains("\n") { return nil }
        // A space after something that matches nothing: it was just writing.
        if query.hasSuffix(" "), Command.matching(query).isEmpty { return nil }
        return query
    }
}

// MARK: - Model headings

extension NSAttributedString.Key {
    /// Marks a model's heading line inside the writing.
    static let stepID = NSAttributedString.Key("dabba.stepID")
    static let stepMethod = NSAttributedString.Key("dabba.stepMethod")
    /// On the line break that closes a model's box.
    static let stepEnd = NSAttributedString.Key("dabba.stepEnd")
    /// A chance tag ("30%") in a decision tree.
    static let chance = NSAttributedString.Key("dabba.chance")
}

struct HeadingAnchor: Equatable {
    let id: UUID
    let method: MethodID
    let anchor: Int
    /// The line break that closes the box; -1 while it's still open.
    var end: Int = -1
}

/// Asks the text view to put a model's heading at the cursor.
struct HeadingRequest: Equatable {
    let token: Int
    let id: UUID
    let method: MethodID
}

/// What the page asks of the text view about models, and hears back.
struct ModelHooks {
    var saved: [HeadingAnchor] = []
    var insert: HeadingRequest?
    /// Bumped for ⌘↑: jump to the start of the previous model.
    var previousRequest = 0
    /// Heading positions and box ends in the text, to keep steps current.
    var moved: (_ starts: [UUID: Int], _ ends: [UUID: Int]) -> Void = { _, _ in }
    /// The step whose box the cursor is in; nil is the plain page (Catch).
    var current: (UUID?) -> Void = { _ in }
}

/// A called model shows as a small heading line inline in the writing, right
/// where it was called. The writing under it belongs to that model until the
/// next heading.
enum ModelHeadings {
    static func attributes(id: UUID, method: MethodID) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 28
        style.paragraphSpacing = 4
        return [.font: PlatformFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: Paper.Platform.inkMuted,
                .paragraphStyle: style,
                .stepID: id.uuidString,
                .stepMethod: method.rawValue]
    }

    /// Puts saved headings back. A heading only returns if its text is still
    /// where the step says it is.
    static func apply(_ headings: [HeadingAnchor], to text: NSMutableAttributedString) {
        let string = text.string as NSString
        for heading in headings {
            let name = heading.method.method.name
            let range = NSRange(location: heading.anchor, length: (name as NSString).length)
            guard NSMaxRange(range) <= string.length, string.substring(with: range) == name else { continue }
            text.addAttributes(attributes(id: heading.id, method: heading.method), range: range)
            if heading.end >= 0, heading.end < string.length, string.character(at: heading.end) == 10 {
                text.addAttribute(.stepEnd, value: heading.id.uuidString,
                                  range: NSRange(location: heading.end, length: 1))
            }
        }
    }

    /// Where each closed box ends: its closing line break.
    static func ends(in text: NSAttributedString) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        text.enumerateAttribute(.stepEnd, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let raw = value as? String, let id = UUID(uuidString: raw) { result[id] = range.location }
        }
        return result
    }

    static func headings(in text: NSAttributedString) -> [(id: UUID, method: MethodID, range: NSRange)] {
        var result: [(UUID, MethodID, NSRange)] = []
        text.enumerateAttribute(.stepID, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let raw = value as? String, let id = UUID(uuidString: raw) else { return }
            let methodRaw = text.attribute(.stepMethod, at: range.location, effectiveRange: nil) as? String
            result.append((id, MethodID(rawValue: methodRaw ?? "") ?? .catchAll, range))
        }
        return result
    }

    static func anchors(in text: NSAttributedString) -> [UUID: Int] {
        Dictionary(headings(in: text).map { ($0.id, $0.range.location) }, uniquingKeysWith: { a, _ in a })
    }

    /// Space between a model's box edge and its text.
    static let boxInset: CGFloat = 14

    /// Each model's box: from its heading to its closing line break, or up to
    /// the next heading or the end if it's still open.
    static func sections(in text: NSAttributedString) -> [(id: UUID, method: MethodID, range: NSRange, closed: Bool)] {
        let all = headings(in: text)
        let closes = ends(in: text)
        return all.enumerated().map { index, heading in
            var end = index + 1 < all.count ? all[index + 1].range.location : text.length
            var closed = false
            if let close = closes[heading.id], close >= heading.range.location, close + 1 <= end {
                end = close + 1
                closed = true
            }
            return (heading.id, heading.method,
                    NSRange(location: heading.range.location, length: end - heading.range.location), closed)
        }
    }

    /// How the grey explanation under a new heading is drawn.
    static var explanationAttributes: [NSAttributedString.Key: Any] {
        [.font: Paper.Platform.page,
         .foregroundColor: Paper.Platform.inkMuted.withAlphaComponent(0.55)]
    }

    /// The full height of a model's explanation, wrapped to the box's width.
    static func explanationHeight(_ method: MethodID, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        let bounds = (method.method.explanation as NSString).boundingRect(
            with: CGSize(width: width - 2 * boxInset, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: explanationAttributes, context: nil)
        return ceil(bounds.height)
    }

    /// Indents each model's section so its text sits inside its box, and
    /// makes room under an empty heading for its whole explanation. Run after
    /// every edit, so new lines in a box pick up the indent too.
    static func styleSections(_ storage: NSTextStorage, width: CGFloat = 0) {
        #if os(macOS)
        let all = sections(in: storage)
        let string = storage.string as NSString
        let placeholders = Dictionary(emptyLines(in: storage).map { ($0.location, $0.method) },
                                      uniquingKeysWith: { a, _ in a })
        // One line of writing: the font's line height plus the page's line spacing.
        let lineHeight = ceil(Paper.Platform.page.ascender - Paper.Platform.page.descender
                              + Paper.Platform.page.leading) + Paper.pageLineSpacing
        storage.beginEditing()
        // Text outside every box goes back to the plain page.
        storage.enumerateAttribute(.paragraphStyle,
                                   in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let style = value as? NSParagraphStyle, style.headIndent == boxInset,
                  !all.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) else { return }
            storage.addAttribute(.paragraphStyle,
                                 value: Strike.baseAttributes[.paragraphStyle]!, range: range)
        }
        for section in all where section.range.length > 0 {
            string.enumerateSubstrings(in: section.range, options: [.byParagraphs, .substringNotRequired]) {
                _, _, paragraph, _ in
                guard paragraph.length > 0 else { return }
                let current = storage.attribute(.paragraphStyle, at: paragraph.location,
                                                effectiveRange: nil) as? NSParagraphStyle
                let style = (current?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                let isHeading = storage.attribute(.stepID, at: paragraph.location, effectiveRange: nil) != nil
                style.firstLineHeadIndent = boxInset
                style.headIndent = boxInset
                style.tailIndent = -boxInset
                if section.method == .decisionTree, !isHeading {
                    // Branches: each leading tab steps in one level, and
                    // wrapped lines stay under their branch.
                    let level = level(ofLineAt: paragraph.location, in: string)
                    style.tabStops = (1...maxBranchLevel + 1).map {
                        NSTextTab(textAlignment: .left, location: boxInset + CGFloat($0) * branchIndent)
                    }
                    style.defaultTabInterval = branchIndent
                    style.headIndent = boxInset + CGFloat(level) * branchIndent
                    // Options (the top level) read as the tree's nodes.
                    let weight: PlatformFont.Weight = level == 0 ? .semibold : .regular
                    let font = PlatformFont.systemFont(ofSize: 18, weight: weight)
                    storage.enumerateAttribute(.font, in: paragraph) { value, run, _ in
                        guard storage.attribute(.chance, at: run.location, effectiveRange: nil) == nil else { return }
                        if (value as? PlatformFont) != font { storage.addAttribute(.font, value: font, range: run) }
                    }
                }
                if !isHeading {
                    style.lineSpacing = Paper.pageLineSpacing
                    if let method = placeholders[paragraph.location] {
                        style.paragraphSpacing = max(0, explanationHeight(method, width: width) - lineHeight + 4)
                    } else {
                        style.paragraphSpacing = 0
                    }
                }
                if current != style {
                    storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
                }
            }
            if section.method == .decisionTree { styleChances(in: section.range, storage: storage) }
        }
        storage.endEditing()
        #endif
    }

    /// Chances in a tree ("30%", "~30%") become small muted tags. Earlier
    /// tags are reset first, so editing a number updates its tag.
    static func styleChances(in range: NSRange, storage: NSTextStorage) {
        storage.enumerateAttribute(.chance, in: range) { value, run, _ in
            guard value != nil else { return }
            let struck = ((storage.attribute(.strikethroughStyle, at: run.location, effectiveRange: nil) as? Int) ?? 0) != 0
            storage.addAttributes([.font: Paper.Platform.page,
                                   .foregroundColor: struck ? Paper.Platform.inkMuted : Paper.Platform.ink],
                                  range: run)
            storage.removeAttribute(.chance, range: run)
        }
        for match in chancePattern.matches(in: storage.string, range: range) {
            storage.addAttributes([.font: PlatformFont.systemFont(ofSize: 13, weight: .medium),
                                   .foregroundColor: Paper.Platform.inkMuted,
                                   .chance: true],
                                  range: match.range)
        }
    }

    // MARK: Decision tree

    /// How far each branch level steps in.
    static let branchIndent: CGFloat = 32
    static let maxBranchLevel = 3

    /// Branch level of a line: its leading tabs.
    static func level(ofLineAt location: Int, in string: NSString) -> Int {
        let line = string.lineRange(for: NSRange(location: min(location, string.length), length: 0))
        var level = 0
        while level < line.length, string.character(at: line.location + level) == 9 { level += 1 }  // "\t"
        return level
    }

    /// True when `location` is inside a Decision tree box.
    static func isInTree(_ location: Int, in text: NSAttributedString) -> Bool {
        guard let id = step(at: location, in: text) else { return false }
        return sections(in: text).first { $0.id == id }?.method == .decisionTree
    }

    /// A chance like "30%" or "~30%", shown as a small muted tag.
    static let chancePattern = try! NSRegularExpression(pattern: "~?\\b\\d{1,3}\\s?%")

    /// Where a heading's writing starts: the line after it.
    static func contentStart(of range: NSRange) -> Int { NSMaxRange(range) + 1 }

    /// The step whose box the cursor at `location` is in; nil is the plain page.
    static func step(at location: Int, in text: NSAttributedString) -> UUID? {
        sections(in: text).last { section in
            let end = NSMaxRange(section.range)
            let inside = location > section.range.location && location < end
            let atOpenEnd = !section.closed && location == end && end == text.length
            return inside || atOpenEnd
        }?.id
    }

    /// Return on an empty last line inside a box closes the box there: the
    /// line break before the cursor becomes the box's end, and the cursor is
    /// back on the plain page. Returns the step closed, or nil to type normally.
    static func close(at caret: Int, in storage: NSTextStorage) -> UUID? {
        let string = storage.string as NSString
        guard caret > 0, string.character(at: caret - 1) == 10,
              caret == string.length || string.character(at: caret) == 10,
              let id = step(at: caret, in: storage),
              let section = sections(in: storage).first(where: { $0.id == id }) else { return nil }
        // Only from the box's last line: nothing but line breaks after it.
        let rest = NSRange(location: caret, length: NSMaxRange(section.range) - caret)
        guard rest.length <= 0 || string.substring(with: rest).allSatisfy({ $0 == "\n" }) else { return nil }
        storage.addAttribute(.stepEnd, value: id.uuidString, range: NSRange(location: caret - 1, length: 1))
        return id
    }

    /// Empty lines right under a heading, where the grey explanation shows.
    static func emptyLines(in text: NSAttributedString) -> [(location: Int, method: MethodID)] {
        let string = text.string as NSString
        return headings(in: text).compactMap { heading in
            let after = NSMaxRange(heading.range)
            guard after < string.length, string.character(at: after) == 10 else { return nil }
            let line = after + 1
            let empty = line == string.length || string.character(at: line) == 10
            return empty ? (line, heading.method) : nil
        }
    }

    /// Inserts a heading at `caret` on its own line, with an empty line under
    /// it to write on. Returns where the cursor goes: that empty line.
    static func insert(_ request: HeadingRequest, into storage: NSTextStorage, at caret: Int) -> Int {
        let string = storage.string as NSString
        let caret = min(caret, string.length)
        let block = NSMutableAttributedString()
        if caret > 0, string.character(at: caret - 1) != 10 {
            block.append(NSAttributedString(string: "\n", attributes: Strike.baseAttributes))
        }
        block.append(NSAttributedString(string: request.method.method.name,
                                        attributes: attributes(id: request.id, method: request.method)))
        block.append(NSAttributedString(string: "\n", attributes: Strike.baseAttributes))
        let cursor = caret + block.length
        let lineIsEmpty = caret == string.length || string.character(at: caret) == 10
        // The line to write on always gets its own line break, so it can take
        // the box's indent and room for the explanation.
        if !lineIsEmpty || caret == string.length {
            block.append(NSAttributedString(string: "\n", attributes: Strike.baseAttributes))
        }
        storage.replaceCharacters(in: NSRange(location: caret, length: 0), with: block)
        return cursor
    }

    /// ⌘↑: the start of the current model's writing, or of the one before it
    /// if you're already there. Before any heading is the top of the page.
    static func previousStart(from caret: Int, in text: NSAttributedString) -> Int {
        headings(in: text).map { contentStart(of: $0.range) }.last { $0 < caret } ?? 0
    }
}

// MARK: - iOS

#if os(iOS)
/// The writing area. `focusRequest` focuses it each time the value changes.
/// Branching tangents is Mac-only for now; marks still show and keep their place.
struct PageTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var struck: [Int]
    var focusRequest: Int
    var tangents = TangentHooks()
    var commands = CommandHooks()
    var models = ModelHooks()
    /// Past sessions: shown exactly as written, but not editable.
    var readOnly = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isEditable = !readOnly
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.tintColor = Paper.Platform.accent
        view.spellCheckingType = .no
        view.autocorrectionType = .no
        view.keyboardDismissMode = .interactive
        let page = Strike.attributed(text: text, struck: struck)
        TangentMarks.apply(tangents.saved, to: page)
        ModelHeadings.apply(models.saved, to: page)
        view.attributedText = page
        view.linkTextAttributes = [.foregroundColor: Paper.Platform.inkMuted]
        view.typingAttributes = Strike.baseAttributes
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if focusRequest != context.coordinator.handledFocusRequest {
            context.coordinator.handledFocusRequest = focusRequest
            DispatchQueue.main.async { view.becomeFirstResponder() }
        }
        if commands.consumeRequest != context.coordinator.handledConsume {
            context.coordinator.handledConsume = commands.consumeRequest
            DispatchQueue.main.async { context.coordinator.consumeCommand(view) }
        }
        if let request = models.insert, request.token != context.coordinator.handledInsert {
            context.coordinator.handledInsert = request.token
            DispatchQueue.main.async { context.coordinator.insertHeading(view, request) }
        }
        if models.previousRequest != context.coordinator.handledPrevious {
            context.coordinator.handledPrevious = models.previousRequest
            DispatchQueue.main.async { context.coordinator.jumpToPrevious(view) }
        }
        if let removal = tangents.remove, removal.token != context.coordinator.handledRemoval {
            context.coordinator.handledRemoval = removal.token
            DispatchQueue.main.async { context.coordinator.removeMark(view, removal.id) }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PageTextView
        var handledFocusRequest = 0
        var handledConsume = 0
        var handledInsert = 0
        var handledPrevious = 0
        var handledRemoval = 0
        private var lastCurrent: UUID??
        /// Where the `/` or `@` of an open command sits, and which list it opens.
        private var commandStart: Int?
        private var commandScope: CommandScope = .modes

        init(_ parent: PageTextView) { self.parent = parent }

        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard view.markedTextRange == nil else { return true }
            if commandStart != nil, text == "\n" {
                if parent.commands.key(.enter) { consumeCommand(view); return false }
                endCommand()
            }
            if text == "\n", view.selectedRange.length == 0,
               ModelHeadings.close(at: view.selectedRange.location, in: view.textStorage) != nil {
                view.typingAttributes = Strike.baseAttributes
                sync(view)
                reportCurrent(view)
                return false
            }
            if let scope = CommandScope(trigger: text), view.selectedRange.length == 0,
               CommandHooks.startsLine(view.textStorage.string as NSString, at: range.location) {
                commandStart = range.location
                commandScope = scope
                return true
            }
            let before = NSAttributedString(attributedString: view.textStorage)
            let selection = view.selectedRange
            guard let caret = Strike.apply(to: view.textStorage, edit: range,
                                           selection: selection, replacement: text)
            else { return true }
            view.selectedRange = caret
            view.typingAttributes = Strike.baseAttributes
            registerUndo(view, restoring: before, selection: selection)
            sync(view)
            return false
        }

        func textViewDidChange(_ view: UITextView) {
            sync(view)
            updateCommand(view)
        }

        /// New typing is always plain ink, even right after struck words.
        func textViewDidChangeSelection(_ view: UITextView) {
            view.typingAttributes = Strike.baseAttributes
            updateCommand(view)
            reportCurrent(view)
        }

        // MARK: Commands

        private func updateCommand(_ view: UITextView) {
            guard let start = commandStart else { return }
            let caret = view.selectedRange.location
            guard let query = CommandHooks.query(in: view.textStorage.string as NSString,
                                                 start: start, caret: caret),
                  let position = view.selectedTextRange?.end else { endCommand(); return }
            var rect = view.caretRect(for: position)
            rect.origin.y -= view.contentOffset.y
            parent.commands.query(query, commandScope, rect)
        }

        /// Removes the typed `/command` once it has run.
        func consumeCommand(_ view: UITextView) {
            guard let start = commandStart else { return }
            let caret = max(view.selectedRange.location, start + 1)
            let range = NSRange(location: start, length: min(caret, view.textStorage.length) - start)
            view.textStorage.replaceCharacters(in: range, with: "")
            view.selectedRange = NSRange(location: start, length: 0)
            endCommand()
            sync(view)
        }

        private func endCommand() {
            commandStart = nil
            parent.commands.query(nil, commandScope, .zero)
        }

        private func sync(_ view: UITextView) {
            parent.text = view.textStorage.string
            parent.struck = Strike.flatRanges(in: view.textStorage)
            parent.tangents.moved(TangentMarks.anchors(in: view.textStorage))
            parent.models.moved(ModelHeadings.anchors(in: view.textStorage), ModelHeadings.ends(in: view.textStorage))
            ModelHeadings.styleSections(view.textStorage)
        }

        func removeMark(_ view: UITextView, _ id: UUID) {
            let caret = view.selectedRange
            guard TangentMarks.removeMark(id, from: view.textStorage) else { return }
            view.selectedRange = NSRange(location: min(caret.location, view.textStorage.length), length: 0)
            view.undoManager?.removeAllActions()
            sync(view)
        }

        // MARK: Models

        func insertHeading(_ view: UITextView, _ request: HeadingRequest) {
            let caret = ModelHeadings.insert(request, into: view.textStorage, at: view.selectedRange.location)
            view.selectedRange = NSRange(location: caret, length: 0)
            view.typingAttributes = Strike.baseAttributes
            view.undoManager?.removeAllActions()
            sync(view)
            reportCurrent(view)
            view.becomeFirstResponder()
        }

        func jumpToPrevious(_ view: UITextView) {
            let target = ModelHeadings.previousStart(from: view.selectedRange.location, in: view.textStorage)
            view.selectedRange = NSRange(location: target, length: 0)
            view.scrollRangeToVisible(view.selectedRange)
            reportCurrent(view)
        }

        private func reportCurrent(_ view: UITextView) {
            let id = ModelHeadings.step(at: view.selectedRange.location, in: view.textStorage)
            guard lastCurrent != .some(id) else { return }
            lastCurrent = .some(id)
            parent.models.current(id)
        }

        /// The text view's own undo history can't follow edits made straight to
        /// its storage, so a strike starts a fresh history that can undo it.
        private func registerUndo(_ view: UITextView, restoring snapshot: NSAttributedString,
                                  selection: NSRange) {
            guard let undo = view.undoManager else { return }
            undo.removeAllActions()
            undo.registerUndo(withTarget: self) { coordinator in
                coordinator.restore(view, to: snapshot, selection: selection)
            }
        }

        private func restore(_ view: UITextView, to snapshot: NSAttributedString, selection: NSRange) {
            let current = NSAttributedString(attributedString: view.textStorage)
            let currentSelection = view.selectedRange
            view.undoManager?.registerUndo(withTarget: self) { coordinator in
                coordinator.restore(view, to: current, selection: currentSelection)
            }
            view.textStorage.setAttributedString(snapshot)
            view.selectedRange = selection
            sync(view)
        }
    }
}
#endif

// MARK: - macOS

#if os(macOS)
/// The writing area. `focusRequest` focuses it each time the value changes.
/// ⌘] branches the selection into a tangent; clicking a mark opens it.
struct PageTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var struck: [Int]
    var focusRequest: Int
    var tangents = TangentHooks()
    var commands = CommandHooks()
    var models = ModelHooks()
    /// Past sessions: shown exactly as written, but not editable.
    var readOnly = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        // An explicit TextKit 1 stack, so mark positions can be measured.
        let size = scroll.contentSize
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: size.width,
                                                              height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        context.coordinator.storage = storage

        let view = PageNSTextView(frame: NSRect(origin: .zero, size: size), textContainer: container)
        view.minSize = NSSize(width: 0, height: size.height)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainerInset = .zero

        view.delegate = context.coordinator
        view.onBranch = { [weak coordinator = context.coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.branch(view)
        }
        view.drawsBackground = false
        view.isEditable = !readOnly
        view.isRichText = true
        view.allowsUndo = true
        view.importsGraphics = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.insertionPointColor = Paper.Platform.accent
        view.linkTextAttributes = [.foregroundColor: Paper.Platform.inkMuted,
                                   .cursor: NSCursor.pointingHand]

        let page = Strike.attributed(text: text, struck: struck)
        TangentMarks.apply(tangents.saved, to: page)
        ModelHeadings.apply(models.saved, to: page)
        storage.setAttributedString(page)
        ModelHeadings.styleSections(storage, width: size.width)
        view.typingAttributes = Strike.baseAttributes

        scroll.documentView = view
        context.coordinator.textView = view
        context.coordinator.observe(scroll: scroll, view: view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if focusRequest != context.coordinator.handledFocusRequest,
           let view = scroll.documentView as? NSTextView {
            context.coordinator.handledFocusRequest = focusRequest
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        guard let view = scroll.documentView as? NSTextView else { return }
        if commands.consumeRequest != context.coordinator.handledConsume {
            context.coordinator.handledConsume = commands.consumeRequest
            DispatchQueue.main.async { context.coordinator.consumeCommand(view) }
        }
        if let request = models.insert, request.token != context.coordinator.handledInsert {
            context.coordinator.handledInsert = request.token
            DispatchQueue.main.async { context.coordinator.insertHeading(view, request) }
        }
        if models.previousRequest != context.coordinator.handledPrevious {
            context.coordinator.handledPrevious = models.previousRequest
            DispatchQueue.main.async { context.coordinator.jumpToPrevious(view) }
        }
        if let removal = tangents.remove, removal.token != context.coordinator.handledRemoval {
            context.coordinator.handledRemoval = removal.token
            DispatchQueue.main.async { context.coordinator.removeMark(view, removal.id) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PageTextView
        var handledFocusRequest = 0
        var handledConsume = 0
        var handledInsert = 0
        var handledPrevious = 0
        var handledRemoval = 0
        private var lastCurrent: UUID??
        /// Where the `/` or `@` of an open command sits, and which list it opens.
        private var commandStart: Int?
        private var commandScope: CommandScope = .modes
        var storage: NSTextStorage?          // owns the TextKit stack
        weak var textView: NSTextView?
        private var lastOnScreen: [UUID: CGFloat] = [:]

        init(_ parent: PageTextView) { self.parent = parent }

        deinit { NotificationCenter.default.removeObserver(self) }

        func observe(scroll: NSScrollView, view: NSTextView) {
            scroll.contentView.postsBoundsChangedNotifications = true
            view.postsFrameChangedNotifications = true
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(layoutMoved),
                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            center.addObserver(self, selector: #selector(layoutMoved),
                               name: NSView.frameDidChangeNotification, object: view)
            center.addObserver(self, selector: #selector(branchRequested),
                               name: .branchTangent, object: nil)
            DispatchQueue.main.async { self.reportOnScreen() }
        }

        @objc private func layoutMoved() {
            // A new width re-wraps explanations, so their room may change.
            if let view = textView, let storage = view.textStorage {
                ModelHeadings.styleSections(storage, width: view.textContainer?.size.width ?? 0)
            }
            reportOnScreen()
        }

        /// The Page ▸ Branch Tangent menu item (⌘]). Only the page that has
        /// focus branches, so ⌘] inside a tangent note does nothing.
        @objc func branchRequested() {
            guard let view = textView else { return }
            let focused = view.window?.firstResponder === view
            pageLog.notice("branch requested, page focused: \(focused, privacy: .public)")
            if focused { branch(view) }
        }

        // MARK: Editing

        func textView(_ view: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            // nil means an attribute-only change; let those through.
            guard let replacement = replacementString, !view.hasMarkedText(),
                  let storage = view.textStorage else { return true }
            if replacement == "\n", view.selectedRange().length == 0,
               ModelHeadings.close(at: view.selectedRange().location, in: storage) != nil {
                view.typingAttributes = Strike.baseAttributes
                sync(view)
                reportCurrent(view)
                return false
            }
            if let scope = CommandScope(trigger: replacement), view.selectedRange().length == 0,
               CommandHooks.startsLine(storage.string as NSString, at: range.location) {
                commandStart = range.location
                commandScope = scope
                return true
            }
            let before = NSAttributedString(attributedString: storage)
            let selection = view.selectedRange()
            guard let caret = Strike.apply(to: storage, edit: range,
                                           selection: selection, replacement: replacement)
            else { return true }
            view.setSelectedRange(caret)
            view.typingAttributes = Strike.baseAttributes
            registerUndo(view, restoring: before, selection: selection)
            sync(view)
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            sync(view)
            updateCommand(view)
        }

        /// New typing is always plain ink, even right after struck words or a mark.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            view.typingAttributes = typingAttributes(in: view)
            updateCommand(view)
            reportCurrent(view)
        }

        /// Plain ink, indented when the cursor is inside a model's box.
        private func typingAttributes(in view: NSTextView) -> [NSAttributedString.Key: Any] {
            var attributes = Strike.baseAttributes
            guard let storage = view.textStorage,
                  ModelHeadings.step(at: view.selectedRange().location, in: storage) != nil else { return attributes }
            let style = NSMutableParagraphStyle()
            style.lineSpacing = Paper.pageLineSpacing
            style.firstLineHeadIndent = ModelHeadings.boxInset
            style.headIndent = ModelHeadings.boxInset
            style.tailIndent = -ModelHeadings.boxInset
            attributes[.paragraphStyle] = style
            return attributes
        }

        // MARK: Commands

        /// While the command card is open, arrows and Return go to the card
        /// and Escape closes it.
        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard commandStart != nil else { return treeKey(view, selector) }
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                return parent.commands.key(.up)
            case #selector(NSResponder.moveDown(_:)):
                return parent.commands.key(.down)
            case #selector(NSResponder.insertNewline(_:)):
                if parent.commands.key(.enter) { consumeCommand(view); return true }
                endCommand()
                return false
            case #selector(NSResponder.cancelOperation(_:)):
                // Escape cancels: the card closes and the typed `@…` goes too.
                consumeCommand(view)
                return true
            default:
                return false
            }
        }

        // MARK: Decision tree keys

        /// In a Decision tree box, Return does the work: after an option it
        /// starts a branch under it, after a branch another branch, and on an
        /// empty branch it steps back out to the next option. Tab and Shift-Tab
        /// still move a line in or out for deeper trees.
        private func treeKey(_ view: NSTextView, _ selector: Selector) -> Bool {
            guard let storage = view.textStorage,
                  ModelHeadings.isInTree(view.selectedRange().location, in: storage) else { return false }
            let string = storage.string as NSString
            let caret = view.selectedRange().location
            let line = string.lineRange(for: NSRange(location: caret, length: 0))
            let level = ModelHeadings.level(ofLineAt: caret, in: string)
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                guard level < ModelHeadings.maxBranchLevel else { return true }
                shiftLine(view, start: line.location, by: 1)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                if level > 0 { shiftLine(view, start: line.location, by: -1) }
                return true
            case #selector(NSResponder.insertNewline(_:)):
                let content = string.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
                if content.isEmpty && level > 0 {
                    shiftLine(view, start: line.location, by: -1)
                    return true
                }
                if content.isEmpty { return false }      // empty option: normal Return leaves the box
                // After an option, the next line is a branch under it; after a
                // branch, another branch at the same level.
                let next = max(level, 1)
                view.insertText("\n" + String(repeating: "\t", count: next),
                                replacementRange: view.selectedRange())
                return true
            default:
                return false
            }
        }

        private func shiftLine(_ view: NSTextView, start: Int, by delta: Int) {
            guard let storage = view.textStorage else { return }
            let selection = view.selectedRange()
            if delta > 0 {
                storage.insert(NSAttributedString(string: "\t", attributes: Strike.baseAttributes), at: start)
            } else {
                storage.deleteCharacters(in: NSRange(location: start, length: 1))
            }
            view.setSelectedRange(NSRange(location: max(start, selection.location + delta),
                                          length: selection.length))
            sync(view)
        }

        private func updateCommand(_ view: NSTextView) {
            guard let start = commandStart, let storage = view.textStorage else { return }
            let caret = view.selectedRange().location
            guard let query = CommandHooks.query(in: storage.string as NSString,
                                                 start: start, caret: caret),
                  let layout = view.layoutManager, let container = view.textContainer
            else { endCommand(); return }
            let glyph = layout.glyphIndexForCharacter(at: max(caret - 1, 0))
            var rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            rect.origin.x += view.textContainerOrigin.x
            rect.origin.y += view.textContainerOrigin.y - (view.enclosingScrollView?.contentView.bounds.minY ?? 0)
            parent.commands.query(query, commandScope, rect)
        }

        /// Removes the typed `/command` once it has run.
        func consumeCommand(_ view: NSTextView) {
            guard let start = commandStart, let storage = view.textStorage else { return }
            let caret = max(view.selectedRange().location, start + 1)
            let range = NSRange(location: start, length: min(caret, storage.length) - start)
            storage.replaceCharacters(in: range, with: "")
            view.setSelectedRange(NSRange(location: start, length: 0))
            endCommand()
            sync(view)
        }

        private func endCommand() {
            commandStart = nil
            parent.commands.query(nil, commandScope, .zero)
        }

        func textView(_ view: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let id = TangentMarks.id(from: link) else { return false }
            parent.tangents.open(id)
            return true
        }

        // MARK: Tangents

        /// ⌘]: the selection leaves the page for a new tangent, and a number
        /// mark takes its place. With nothing selected, an empty tangent opens.
        func branch(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let selection = view.selectedRange()
            let picked = (storage.string as NSString).substring(with: selection)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let (id, mark) = parent.tangents.branch(picked, selection.location)
            pageLog.notice("branched \(picked.count, privacy: .public) chars, mark '\(mark, privacy: .public)'")
            guard !mark.isEmpty else { return }

            let markText = NSAttributedString(string: mark, attributes: TangentMarks.attributes(for: id))
            storage.replaceCharacters(in: selection, with: markText)
            view.setSelectedRange(NSRange(location: selection.location + markText.length, length: 0))
            view.typingAttributes = Strike.baseAttributes
            view.undoManager?.removeAllActions()   // undo can't follow a branch yet
            sync(view)
        }

        private func sync(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            parent.text = storage.string
            parent.struck = Strike.flatRanges(in: storage)
            parent.tangents.moved(TangentMarks.anchors(in: storage))
            parent.models.moved(ModelHeadings.anchors(in: storage), ModelHeadings.ends(in: storage))
            ModelHeadings.styleSections(storage, width: view.textContainer?.size.width ?? 0)
            view.needsDisplay = true   // boxes, and grey explanations under empty headings
            DispatchQueue.main.async { self.reportOnScreen() }
        }

        func removeMark(_ view: NSTextView, _ id: UUID) {
            guard let storage = view.textStorage else { return }
            let caret = view.selectedRange()
            guard TangentMarks.removeMark(id, from: storage) else { return }
            view.setSelectedRange(NSRange(location: min(caret.location, storage.length), length: 0))
            view.undoManager?.removeAllActions()
            sync(view)
        }

        // MARK: Models

        func insertHeading(_ view: NSTextView, _ request: HeadingRequest) {
            guard let storage = view.textStorage else { return }
            let caret = ModelHeadings.insert(request, into: storage, at: view.selectedRange().location)
            view.setSelectedRange(NSRange(location: caret, length: 0))
            view.typingAttributes = Strike.baseAttributes
            view.undoManager?.removeAllActions()
            sync(view)
            reportCurrent(view)
            view.scrollRangeToVisible(view.selectedRange())
            view.window?.makeFirstResponder(view)
        }

        func jumpToPrevious(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let target = ModelHeadings.previousStart(from: view.selectedRange().location, in: storage)
            view.setSelectedRange(NSRange(location: target, length: 0))
            view.scrollRangeToVisible(view.selectedRange())
            view.window?.makeFirstResponder(view)
            reportCurrent(view)
        }

        private func reportCurrent(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let id = ModelHeadings.step(at: view.selectedRange().location, in: storage)
            guard lastCurrent != .some(id) else { return }
            lastCurrent = .some(id)
            parent.models.current(id)
        }

        /// Measures where each mark is drawn, relative to the visible top of
        /// the writing area, so notes can sit level with their marks.
        private func reportOnScreen() {
            guard let view = textView, let storage = view.textStorage,
                  let layout = view.layoutManager, let container = view.textContainer else { return }
            let scrollTop = view.enclosingScrollView?.contentView.bounds.minY ?? 0
            var result: [UUID: CGFloat] = [:]
            storage.enumerateAttribute(.tangentID,
                                       in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard let raw = value as? String, let id = UUID(uuidString: raw) else { return }
                let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
                result[id] = rect.minY + view.textContainerOrigin.y - scrollTop
            }
            guard result != lastOnScreen else { return }
            lastOnScreen = result
            parent.tangents.onScreen(result)
        }

        // MARK: Undo

        /// The text view's own undo history can't follow edits made straight to
        /// its storage, so a strike starts a fresh history that can undo it.
        private func registerUndo(_ view: NSTextView, restoring snapshot: NSAttributedString,
                                  selection: NSRange) {
            guard let undo = view.undoManager else { return }
            undo.removeAllActions()
            undo.registerUndo(withTarget: self) { coordinator in
                coordinator.restore(view, to: snapshot, selection: selection)
            }
        }

        private func restore(_ view: NSTextView, to snapshot: NSAttributedString, selection: NSRange) {
            guard let storage = view.textStorage else { return }
            let current = NSAttributedString(attributedString: storage)
            let currentSelection = view.selectedRange()
            view.undoManager?.registerUndo(withTarget: self) { coordinator in
                coordinator.restore(view, to: current, selection: currentSelection)
            }
            storage.setAttributedString(snapshot)
            view.setSelectedRange(selection)
            sync(view)
        }
    }
}

/// Pastes as plain text, so pasted styling never lands on the page.
final class PageNSTextView: NSTextView {
    var onBranch: (() -> Void)?

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    /// Each model's section sits in a softly tinted box with rounded corners.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let storage = textStorage, let layout = layoutManager,
              let container = textContainer else { return }
        for section in ModelHeadings.sections(in: storage) {
            guard let tint = Paper.Platform.box(section.method), section.range.length > 0 else { continue }
            // Lay the whole box out before measuring it, so a line that just
            // wrapped is counted and the text never spills past the box.
            layout.ensureLayout(forCharacterRange: section.range)
            let first = layout.glyphIndexForCharacter(at: section.range.location)
            var top = layout.lineFragmentUsedRect(forGlyphAt: first, effectiveRange: nil).minY
            let lastChar = NSMaxRange(section.range) - 1
            let last = layout.glyphIndexForCharacter(at: lastChar)
            var bottom = layout.lineFragmentUsedRect(forGlyphAt: last, effectiveRange: nil).maxY
            let glyphs = layout.glyphRange(forCharacterRange: section.range, actualCharacterRange: nil)
            bottom = max(bottom, layout.boundingRect(forGlyphRange: glyphs, in: container).maxY)
            // A section that ends the page on an empty line includes that line.
            if !section.closed, NSMaxRange(section.range) == storage.length,
               (storage.string as NSString).character(at: lastChar) == 10 {
                bottom = max(bottom, layout.extraLineFragmentUsedRect.maxY)
            }
            // Room for the whole explanation under an empty heading.
            for line in ModelHeadings.emptyLines(in: storage)
            where NSLocationInRange(line.location, section.range) || line.location == NSMaxRange(section.range) {
                let lineTop = line.location >= storage.length
                    ? layout.extraLineFragmentRect.minY
                    : layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: line.location),
                                              effectiveRange: nil).minY
                bottom = max(bottom, lineTop + ModelHeadings.explanationHeight(line.method,
                                                                               width: container.size.width))
            }
            top += textContainerOrigin.y - 10
            bottom += textContainerOrigin.y + 10
            let box = NSRect(x: textContainerOrigin.x, y: top,
                             width: container.size.width, height: bottom - top)
            tint.setFill()
            NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
            if section.method == .decisionTree { drawBranches(in: section.range) }
        }
    }

    /// Thin lines joining each branch to the line it hangs from.
    private func drawBranches(in range: NSRange) {
        guard let storage = textStorage, let layout = layoutManager else { return }
        let string = storage.string as NSString
        var lines: [(level: Int, rect: NSRect)] = []
        string.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            guard line.location < storage.length,
                  storage.attribute(.stepID, at: line.location, effectiveRange: nil) == nil else { return }
            let glyph = layout.glyphIndexForCharacter(at: line.location)
            let rect = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            lines.append((ModelHeadings.level(ofLineAt: line.location, in: string), rect))
        }
        let path = NSBezierPath()
        path.lineWidth = 1
        let origin = textContainerOrigin
        let inset = ModelHeadings.boxInset, step = ModelHeadings.branchIndent
        for (index, line) in lines.enumerated() where line.level > 0 {
            guard let parent = lines[..<index].last(where: { $0.level == line.level - 1 }) else { continue }
            let x = origin.x + inset + CGFloat(line.level - 1) * step + 6
            let top = origin.y + parent.rect.maxY - Paper.pageLineSpacing
            let mid = origin.y + line.rect.minY + (line.rect.height - Paper.pageLineSpacing) / 2
            let textX = origin.x + inset + CGFloat(line.level) * step - 4
            path.move(to: NSPoint(x: x, y: top))
            path.line(to: NSPoint(x: x, y: mid))
            path.line(to: NSPoint(x: textX, y: mid))
        }
        Paper.Platform.inkMuted.withAlphaComponent(0.6).setStroke()
        path.stroke()
    }

    /// Grey text on the empty line under a model's heading, explaining the
    /// model. It goes away as soon as that line has text.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let storage = textStorage, let layout = layoutManager,
              let container = textContainer else { return }
        let attributes = ModelHeadings.explanationAttributes
        for line in ModelHeadings.emptyLines(in: storage) {
            let rect: NSRect
            if line.location >= storage.length {
                rect = layout.extraLineFragmentRect
            } else {
                let glyph = layout.glyphIndexForCharacter(at: line.location)
                rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            guard rect.height > 0 else { continue }
            let inset = ModelHeadings.boxInset
            let width = container.size.width - 2 * inset
            let box = NSRect(x: rect.minX + textContainerOrigin.x + inset, y: rect.minY + textContainerOrigin.y,
                             width: width,
                             height: ModelHeadings.explanationHeight(line.method, width: container.size.width))
            // Wraps onto as many lines as it needs; the box makes room for it.
            (line.method.method.explanation as NSString).draw(
                with: box, options: [.usesLineFragmentOrigin], attributes: attributes)
        }
    }
}

extension Notification.Name {
    /// Posted by Page ▸ Branch Tangent (⌘]).
    static let branchTangent = Notification.Name("dabba.branchTangent")
}
#endif

import os
let pageLog = Logger(subsystem: "dev.abhilash.Dabba", category: "page")
