import Foundation
import SwiftData

/// Models on the page. Each called model is a step whose heading sits inline
/// in the writing, right where it was called; everything written under the
/// heading belongs to it. The writing before the first heading is Catch.
extension Session {
    /// Switching mode keeps everything written; only suggestions and stem change.
    func switchMode(to id: ModeID) {
        modeID = id.rawValue
        ensureCatchStep()
    }

    /// `@inversion` and friends: a new step for the model. The page puts its
    /// heading at the cursor.
    @discardableResult
    func callMethod(_ method: MethodID, input: String = "") -> Step {
        ensureCatchStep()
        let next = (orderedSteps.last?.order ?? 0) + 1
        let step = Step(order: next, method: method, input: input)
        steps = (steps ?? []) + [step]
        currentStepOrder = step.order
        return step
    }

    /// ⌘↓ in a mode: the suggested model after the furthest one reached so far.
    var nextSuggestedMethod: MethodID? {
        let suggested = mode.suggested
        let reached = orderedSteps.compactMap { suggested.firstIndex(of: $0.method) }.max() ?? 0
        return reached + 1 < suggested.count ? suggested[reached + 1] : nil
    }

    /// Catch is always the first step: the writing before any heading.
    private func ensureCatchStep() {
        if !orderedSteps.contains(where: { $0.method == .catchAll }) {
            steps = (steps ?? []) + [Step(order: 0, method: .catchAll)]
        }
    }
}
