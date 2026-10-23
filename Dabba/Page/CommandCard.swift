import SwiftUI

/// The small list that opens on `/` or ⌘K: modes, then models.
/// Flat, bordered, no shadow.
struct CommandCard: View {
    /// Modes first, then models, in the order shown.
    let commands: [Command]
    let selected: Int
    let onPick: (Command) -> Void

    static let width: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if commands.isEmpty {
                Text("Nothing matches")
                    .font(Paper.label)
                    .foregroundStyle(Paper.inkMuted)
                    .padding(8)
            }
            section("Modes", modes: true)
            section("Models", modes: false)
        }
        .padding(6)
        .frame(width: Self.width, alignment: .leading)
        .background(Paper.paperRaised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Paper.hairline))
    }

    @ViewBuilder
    private func section(_ title: String, modes: Bool) -> some View {
        let rows = commands.enumerated().filter { $0.element.isMode == modes }
        if !rows.isEmpty {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Paper.inkMuted)
                .padding(.horizontal, 8)
                .padding(.top, 6)
            ForEach(rows, id: \.element.id) { index, command in
                row(command, highlighted: index == selected)
            }
        }
    }

    private func row(_ command: Command, highlighted: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(command.id)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(command.isAvailable ? Paper.ink : Paper.inkMuted)
            Spacer(minLength: 8)
            Text(command.isAvailable ? command.detail : "later")
                .font(.system(size: 12))
                .foregroundStyle(Paper.inkMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(highlighted ? Paper.hairline.opacity(0.7) : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { if command.isAvailable { onPick(command) } }
    }
}
