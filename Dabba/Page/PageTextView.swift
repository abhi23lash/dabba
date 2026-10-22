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

    /// Applies a strike when an edit replaces the whole current selection.
    /// Returns the new caret position, or nil to let the edit happen normally.
    static func apply(to storage: NSTextStorage, edit range: NSRange,
                      selection: NSRange, replacement: String) -> NSRange? {
        guard selection.length > 0, NSEqualRanges(range, selection) else { return nil }

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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.tintColor = Paper.Platform.accent
        view.spellCheckingType = .no
        view.autocorrectionType = .no
        view.keyboardDismissMode = .interactive
        let page = Strike.attributed(text: text, struck: struck)
        TangentMarks.apply(tangents.saved, to: page)
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
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PageTextView
        var handledFocusRequest = 0

        init(_ parent: PageTextView) { self.parent = parent }

        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard view.markedTextRange == nil else { return true }
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

        func textViewDidChange(_ view: UITextView) { sync(view) }

        /// New typing is always plain ink, even right after struck words.
        func textViewDidChangeSelection(_ view: UITextView) {
            view.typingAttributes = Strike.baseAttributes
        }

        private func sync(_ view: UITextView) {
            parent.text = view.textStorage.string
            parent.struck = Strike.flatRanges(in: view.textStorage)
            parent.tangents.moved(TangentMarks.anchors(in: view.textStorage))
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
        storage.setAttributedString(page)
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
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PageTextView
        var handledFocusRequest = 0
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

        @objc private func layoutMoved() { reportOnScreen() }

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
        }

        /// New typing is always plain ink, even right after struck words or a mark.
        func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? NSTextView)?.typingAttributes = Strike.baseAttributes
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
            DispatchQueue.main.async { self.reportOnScreen() }
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
}

extension Notification.Name {
    /// Posted by Page ▸ Branch Tangent (⌘]).
    static let branchTangent = Notification.Name("dabba.branchTangent")
}
#endif

import os
let pageLog = Logger(subsystem: "dev.abhilash.Dabba", category: "page")
