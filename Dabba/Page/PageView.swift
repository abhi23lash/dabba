import SwiftUI
import SwiftData

/// The writing page: question at the top, free writing in the middle,
/// the landing pinned at the bottom as the destination.
///
/// Fields bind straight to the model, so SwiftData autosaves as you type and
/// nothing is lost if the app quits mid-session.
struct PageView: View {
    @Bindable var session: Session
    let onFinish: () -> Void

    @Environment(\.modelContext) private var context
    /// Pending save, about a second after you stop typing.
    @State private var saveTask: Task<Void, Never>?

    @FocusState private var focus: Field?
    private enum Field { case question, landing }
    /// Bumped to move focus into the writing area (a native text view).
    @State private var textFocusRequest = 0
    /// The tangent note being written in, if any.
    @State private var openTangent: UUID?
    /// Where each tangent's mark is drawn, from the top of the writing area.
    @State private var markPositions: [UUID: CGFloat] = [:]
    /// Asks the text view to take a removed note's mark out of the writing.
    @State private var tangentRemoval: TangentRemoval?
    @State private var removalToken = 0

    /// Design decision: a session can only finish once it has landed.
    private var canFinish: Bool {
        !session.landing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Command card (`/` or ⌘K)
    /// The text typed after `/`; nil when the card is closed.
    @State private var commandQuery: String?
    /// The cursor's rect in the writing area, where the card opens.
    @State private var commandAnchor: CGRect = .zero
    @State private var commandSelection = 0
    /// `/` lists modes, `@` lists models, ⌘K lists both.
    @State private var commandScope: CommandScope = .all
    /// Opened with ⌘K: the card has its own search field.
    @State private var commandFromShortcut = false
    @FocusState private var commandFieldFocused: Bool
    /// Bumped when a command runs by click, so the text view removes `/text`.
    @State private var consumeRequest = 0
    /// Asks the text view to put a model's heading at the cursor.
    @State private var headingRequest: HeadingRequest?
    @State private var headingToken = 0
    /// Bumped for ⌘↑: back to the start of the previous model.
    @State private var previousRequest = 0
    @State private var hoveringModeLabel = false
    /// The faint "type /" hint shows only for the first few sessions.
    @AppStorage("finishedSessions") private var finishedSessions = 0

    private var isIdeas: Bool { session.mode.id == .ideas }
    private var currentMethod: MethodID { session.currentStep?.method ?? .catchAll }
    /// The guide shows in Ideas, or once a model has been called in Open.
    private var showsGuide: Bool { isIdeas || session.orderedSteps.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            TextField("Question", text: $session.question, axis: .vertical)
                .font(Paper.question)
                .foregroundStyle(Paper.ink)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($focus, equals: .question)
                .onSubmit { textFocusRequest += 1 }

            if showsGuide { guide }

            // One page: models called with @ open inline, right where you called them.
            writing

            Rectangle()
                .fill(Paper.hairline)
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if !session.mode.landingStem.isEmpty {
                    Text(session.mode.landingStem)
                        .font(Paper.landing)
                        .foregroundStyle(Paper.ink)
                        .fixedSize()
                }
                TextField(session.mode.landingStem.isEmpty ? "Landing" : "",
                          text: $session.landing, axis: .vertical)
                    .font(Paper.landing)
                    .foregroundStyle(Paper.ink)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .focused($focus, equals: .landing)

                Button("Finish", action: onFinish)
                    .buttonStyle(.plain)
                    .font(Paper.label)
                    .foregroundStyle(canFinish ? Paper.accent : Paper.inkMuted)
                    .disabled(!canFinish)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .frame(maxWidth: Paper.column)
        .padding(.horizontal, Paper.margin)
        .padding(.top, Paper.margin + 24) // clears the corner button
        .padding(.bottom, Paper.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Never lose text: save shortly after any change to the session.
        .onChange(of: session.text) { saveSoon() }
        .onChange(of: session.question) { saveSoon() }
        .onChange(of: session.landing) { saveSoon() }
        .onChange(of: (session.tangents ?? []).map(\.text)) { saveSoon() }
        .task {
            if session.question.isEmpty { focus = .question } else { textFocusRequest += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextMethod)) { _ in
            nextSuggested()
        }
        .onReceive(NotificationCenter.default.publisher(for: .previousMethod)) { _ in
            guard showsGuide else { return }
            previousRequest += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCommands)) { _ in
            commandFromShortcut = true
            commandScope = .all
            commandQuery = ""
            commandSelection = firstAvailable(in: commandList(for: ""))
            commandFieldFocused = true
        }
    }

    // MARK: Commands

    private func commandList(for query: String) -> [Command] {
        let matches = Command.matching(query)
        let modes = matches.filter(\.isMode), models = matches.filter { !$0.isMode }
        switch commandScope {
        case .modes: return modes
        case .models: return models
        case .all: return modes + models
        }
    }

    private var commands: [Command] { commandList(for: commandQuery ?? "") }

    private func firstAvailable(in list: [Command]) -> Int {
        list.firstIndex(where: \.isAvailable) ?? 0
    }

    private func moveSelection(_ delta: Int) {
        let list = commands
        guard !list.isEmpty else { return }
        var index = commandSelection
        repeat {
            index = (index + delta + list.count) % list.count
        } while !list[index].isAvailable && index != commandSelection
        commandSelection = index
    }

    /// Runs the highlighted command. False if there's nothing to run.
    @discardableResult
    private func runSelected() -> Bool {
        let list = commands
        guard list.indices.contains(commandSelection), list[commandSelection].isAvailable else { return false }
        run(list[commandSelection])
        return true
    }

    /// `/ideas` enters a mode where you are; `/inversion` calls a model.
    private func run(_ command: Command) {
        withAnimation(.easeOut(duration: 0.2)) {
            switch command.kind {
            case .mode(let mode):
                session.switchMode(to: mode)
            case .method(let method):
                callInline(method)
            case .later:
                break
            }
        }
        closeCommands()
        if case .mode(.ideas) = command.kind, session.question.isEmpty {
            focus = .question   // the seed: "What's the idea?"
        }
    }

    /// A model opens inline: a new step, with its heading at the cursor.
    private func callInline(_ method: MethodID) {
        let step = session.callMethod(method)
        headingToken += 1
        headingRequest = HeadingRequest(token: headingToken, id: step.id, method: method)
    }

    /// ⌘↓ in a mode: the next suggested model, opened at the cursor.
    private func nextSuggested() {
        guard isIdeas, let method = session.nextSuggestedMethod else { return }
        callInline(method)
    }

    private var modelHooks: ModelHooks {
        ModelHooks(
            saved: session.orderedSteps.filter { $0.method != .catchAll }.map {
                HeadingAnchor(id: $0.id, method: $0.method, anchor: $0.anchor, end: $0.endAnchor)
            },
            insert: headingRequest,
            previousRequest: previousRequest,
            moved: { starts, ends in
                for step in session.orderedSteps {
                    if let anchor = starts[step.id], anchor != step.anchor { step.anchor = anchor }
                    let end = ends[step.id] ?? -1
                    if end != step.endAnchor { step.endAnchor = end }
                }
            },
            current: { id in
                let step = id.flatMap { id in session.orderedSteps.first { $0.id == id } }
                    ?? session.orderedSteps.first { $0.method == .catchAll }
                if let step, step.order != session.currentStepOrder { session.currentStepOrder = step.order }
            }
        )
    }

    private func closeCommands() {
        commandQuery = nil
        commandFromShortcut = false
        commandFieldFocused = false
    }

    private var commandHooks: CommandHooks {
        CommandHooks(
            query: { query, scope, rect in
                guard !commandFromShortcut else { return }
                commandScope = scope
                if query != commandQuery { commandSelection = firstAvailable(in: commandList(for: query ?? "")) }
                commandQuery = query
                commandAnchor = rect
            },
            key: { key in
                switch key {
                case .up: moveSelection(-1); return true
                case .down: moveSelection(1); return true
                case .enter: return runSelected()
                }
            },
            consumeRequest: consumeRequest
        )
    }

    /// The card: at the cursor when typed, at the top of the page with its own
    /// search field when opened with ⌘K.
    @ViewBuilder
    private var commandCard: some View {
        if commandQuery != nil {
            if commandFromShortcut {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Mode or model", text: Binding(
                        get: { commandQuery ?? "" },
                        set: { commandQuery = $0; commandSelection = firstAvailable(in: commandList(for: $0)) }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(width: CommandCard.width)
                        .background(Paper.paperRaised, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Paper.hairline))
                        .focused($commandFieldFocused)
                        .onSubmit { runSelected() }
                        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                        .onKeyPress(.escape) { closeCommands(); textFocusRequest += 1; return .handled }
                    CommandCard(commands: commands, selected: commandSelection) { run($0) }
                }
            } else {
                CommandCard(commands: commands, selected: commandSelection) { command in
                    run(command)
                    consumeRequest += 1
                }
                .offset(y: commandAnchor.maxY + 6)   // commands start a line, so the card lines up with the text
            }
        }
    }

    // MARK: Guide

    /// Where you are: the mode and a dot per suggested model, then the hint.
    private var guide: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isIdeas {
                HStack(spacing: 6) {
                    // The mode's name is also the way out, back to a plain page.
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { session.switchMode(to: .open) }
                        textFocusRequest += 1
                    } label: {
                        HStack(spacing: 3) {
                            Text(session.mode.name)
                            if hoveringModeLabel {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                        }
                        .font(Paper.label)
                        .foregroundStyle(hoveringModeLabel ? Paper.ink : Paper.inkMuted)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveringModeLabel = $0 }
                    .help("Back to a plain page")
                    .accessibilityLabel("Leave \(session.mode.name)")
                    ForEach(session.mode.suggested) { method in
                        Circle()
                            .fill(method == currentMethod ? Paper.ink : Paper.hairline)
                            .frame(width: 6, height: 6)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(guideHint)
                    .font(Paper.label)
                    .foregroundStyle(Paper.inkMuted)
                Spacer()
                #if os(iOS)
                Button("Next") { nextSuggested() }
                .buttonStyle(.plain)
                .font(Paper.label)
                .foregroundStyle(Paper.ink)
                #endif
            }
        }
    }

    private var guideHint: String {
        if isIdeas && currentMethod == .catchAll && session.question.isEmpty { return "What's the idea?" }
        return "\(currentMethod.method.name). \(currentMethod.method.hint)"
    }

    /// The empty page is the invitation. For the first few sessions only, a
    /// faint line says how to find a way in. Selected text that gets deleted is
    /// struck through instead (see `Strike`). On the Mac, tangents sit in a
    /// column to the right of the writing.
    private var writing: some View {
        PageTextView(text: $session.text, struck: $session.struck,
                     focusRequest: textFocusRequest, tangents: tangentHooks,
                     commands: commandHooks, models: modelHooks)
            .overlay(alignment: .topLeading) {
                if session.text.isEmpty && commandQuery == nil && (isIdeas || finishedSessions < 3) {
                    // In Ideas, grey text explains Catch until you type.
                    Text(isIdeas ? MethodID.catchAll.method.explanation
                                 : "Write, or type / for a mode, @ for a model.")
                        .font(Paper.page)
                        .foregroundStyle(Paper.inkMuted.opacity(0.6))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: commandFromShortcut ? .top : .topLeading) { commandCard }
            #if os(macOS)
            .overlay(alignment: .topTrailing) {
                if !(session.tangents ?? []).isEmpty {
                    TangentColumn(tangents: session.tangents ?? [], marks: markPositions,
                                  open: $openTangent, onClose: closeTangent,
                                  onRemove: removeTangent)
                        .offset(x: TangentColumn.width + Paper.margin)
                }
            }
            #endif
    }

    private var tangentHooks: TangentHooks {
        TangentHooks(
            saved: (session.tangents ?? []).map {
                TangentAnchor(id: $0.id, mark: $0.mark, anchor: $0.anchor)
            },
            branch: { picked, location in
                let number = ((session.tangents ?? []).map(\.number).max() ?? 0) + 1
                let tangent = Tangent(number: number, text: picked, anchor: location)
                session.tangents = (session.tangents ?? []) + [tangent]
                // Nothing selected: the tangent opens so you can follow it now.
                // Text selected: it's parked, and you keep writing.
                if picked.isEmpty { openTangent = tangent.id }
                return (tangent.id, tangent.mark)
            },
            open: { openTangent = $0 },
            moved: { anchors in
                for tangent in session.tangents ?? [] {
                    if let anchor = anchors[tangent.id], anchor != tangent.anchor {
                        tangent.anchor = anchor
                    }
                }
            },
            onScreen: { markPositions = $0 },
            remove: tangentRemoval
        )
    }

    /// Saves about a second after the last change, so a crash or force quit
    /// loses at most a moment of typing.
    private func saveSoon() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            try? context.save()
        }
    }

    /// Back to the main text, exactly where you were.
    private func closeTangent() {
        openTangent = nil
        textFocusRequest += 1
    }

    /// Removes a side note and its mark in the writing.
    private func removeTangent(_ tangent: Tangent) {
        if openTangent == tangent.id { openTangent = nil }
        removalToken += 1
        tangentRemoval = TangentRemoval(token: removalToken, id: tangent.id)
        withAnimation(.easeOut(duration: 0.2)) {
            session.tangents = (session.tangents ?? []).filter { $0.id != tangent.id }
        }
        tangent.modelContext?.delete(tangent)
        textFocusRequest += 1
    }
}
