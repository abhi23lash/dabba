import Foundation

/// A session as a plain Markdown file, in the format described in CLAUDE.md
/// ("Local files"). Designed so the file could later be read back as the
/// source of truth.
enum SessionMarkdown {
    static func markdown(for session: Session) -> String {
        var lines: [String] = ["---", "dabba: 1", "id: \(session.id.uuidString)",
                               "mode: \(session.modeID)",
                               "created: \(iso(session.createdAt))"]
        if let finished = session.finishedAt { lines.append("finished: \(iso(finished))") }
        if !session.landing.isEmpty { lines.append("landing: \(yamlValue(session.landing))") }
        lines.append("---")
        let title = session.question.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("# \(title.isEmpty ? "Untitled" : title)")
        lines.append("")

        var output = lines.joined(separator: "\n") + "\n" + body(for: session)
        let notes = (session.tangents ?? []).sorted { $0.number < $1.number }
        if !notes.isEmpty {
            output += "\n"
            for note in notes {
                // Continuation lines are indented so they stay in the footnote.
                let text = note.text.replacingOccurrences(of: "\n", with: "\n    ")
                output += "\n[^\(note.number)]: \(text)"
            }
            output += "\n"
        }
        return output
    }

    /// A safe file name: date plus question, e.g. "2026-10-23 Should I build Dabba.md".
    static func fileName(for session: Session) -> String {
        let date = session.createdAt.formatted(.iso8601.year().month().day())
        var title = session.question.trimmingCharacters(in: .whitespacesAndNewlines)
        title = String(title.map { "/:\\?%*|\"<>\n".contains($0) ? " " : $0 })
            .split(separator: " ").joined(separator: " ")
        if title.count > 60 { title = String(title.prefix(60)).trimmingCharacters(in: .whitespaces) }
        return "\(date) \(title.isEmpty ? "Untitled" : title).md"
    }

    // MARK: Body

    /// The writing with its marks turned into Markdown: struck text as
    /// ~~text~~, model headings as "## Name" closed by <!-- /model -->, and
    /// side note marks as footnote references.
    private static func body(for session: Session) -> String {
        let text = session.text as NSString
        let length = text.length
        // Insertions and replacements at positions in the original text.
        var edits: [(location: Int, length: Int, text: String, order: Int)] = []

        // Struck runs, closed and reopened at each line break.
        for range in Strike.ranges(from: session.struck, length: length) {
            var start = range.location
            let end = NSMaxRange(range)
            while start < end {
                let lineEnd = text.range(of: "\n", options: [], range: NSRange(location: start, length: end - start))
                let segmentEnd = lineEnd.location == NSNotFound ? end : lineEnd.location
                // Markdown strikethrough can't start or end on a space, so the
                // marks hug the first and last visible character.
                var first = start, last = segmentEnd
                while first < last, [32, 9].contains(text.character(at: first)) { first += 1 }
                while last > first, [32, 9].contains(text.character(at: last - 1)) { last -= 1 }
                if last > first {
                    edits.append((first, 0, "~~", 1))
                    edits.append((last, 0, "~~", 0))
                }
                start = segmentEnd + 1
            }
        }

        // Side note marks become footnote references.
        for note in session.tangents ?? [] {
            let mark = note.mark as NSString
            let range = NSRange(location: note.anchor, length: mark.length)
            guard NSMaxRange(range) <= length, text.substring(with: range) == note.mark else { continue }
            edits.append((range.location, range.length, "[^\(note.number)]", 2))
        }

        // Model headings and the end of each box.
        let steps = session.orderedSteps.filter { $0.method != .catchAll }
            .sorted { $0.anchor < $1.anchor }
        for (index, step) in steps.enumerated() {
            let name = step.method.method.name
            let nameRange = NSRange(location: step.anchor, length: (name as NSString).length)
            guard NSMaxRange(nameRange) <= length, text.substring(with: nameRange) == name else { continue }
            // Applied last at this spot, so it lands before any strike mark:
            // "## ~~Name~~", not "~~## Name~~".
            edits.append((step.anchor, 0, "## ", -1))
            // Closed at its saved end if that's still after the heading and
            // before the next one; else just before the next heading or the end.
            let next = index + 1 < steps.count ? steps[index + 1].anchor : length
            var close = next == length ? length : max(next - 1, NSMaxRange(nameRange))
            if step.endAnchor > NSMaxRange(nameRange), step.endAnchor < next { close = step.endAnchor }
            // Applied first at this spot, so it lands after a strike's closing ~~.
            edits.append((close, 0, "\n<!-- /model -->", 4))
        }

        // Apply from the end so earlier positions stay valid. At the same spot,
        // closers go before openers.
        let result = NSMutableString(string: session.text)
        for edit in edits.sorted(by: { ($0.location, $0.order) > ($1.location, $1.order) }) {
            result.replaceCharacters(in: NSRange(location: edit.location, length: edit.length), with: edit.text)
        }
        var body = result as String
        if !body.hasSuffix("\n") { body += "\n" }
        return body
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    /// Quotes a value if it would confuse a YAML reader.
    private static func yamlValue(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let needsQuotes = flat.contains(":") || flat.contains("#") || flat.hasPrefix("-") || flat.contains("\"")
        return needsQuotes ? "\"\(flat.replacingOccurrences(of: "\"", with: "\\\""))\"" : flat
    }
}
