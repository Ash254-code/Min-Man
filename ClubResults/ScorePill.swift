import SwiftUI

/// A reusable capsule "pill" label using ClubStyle colours.
struct ScorePill: View {
    let title: String
    let style: ClubStyle.Style

    init(_ title: String, style: ClubStyle.Style) {
        self.title = title
        self.style = style
    }

    var body: some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.bold)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(style.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(style.background)
            )
            .accessibilityLabel(Text(title))
    }
}

// MARK: - Convenience creators
extension ScorePill {
    static func minMan() -> ScorePill {
        ScorePill("Min Man", style: ClubStyle.ourScoreStyle)
    }

    static func opponent(_ name: String) -> ScorePill {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = cleaned.isEmpty ? "Opponent" : cleaned
        return ScorePill(label, style: ClubStyle.style(for: label))
    }
}
