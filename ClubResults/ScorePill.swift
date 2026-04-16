import SwiftUI

/// A reusable capsule "pill" label using ClubStyle colours.
struct ScorePill: View {
    let title: String
    let style: ClubStyle.Style
    let fixedWidth: CGFloat?

    init(_ title: String, style: ClubStyle.Style, fixedWidth: CGFloat? = nil) {
        self.title = title
        self.style = style
        self.fixedWidth = fixedWidth
    }

    var body: some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.bold)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(style.text)
            .frame(width: fixedWidth, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(style.background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(style.border.opacity(0.95), lineWidth: 1.5)
            )
            .accessibilityLabel(Text(title))
    }
}

// MARK: - Convenience creators
extension ScorePill {
    static func minMan(teamName: String = "Min Man") -> ScorePill {
        let cleaned = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = cleaned.isEmpty ? "Min Man" : cleaned
        let configuration = ClubConfigurationStore.load()
        return ScorePill(
            label,
            style: ClubStyle.style(for: label, configuration: configuration),
            fixedWidth: ClubStyle.standardPillWidth(configuration: configuration)
        )
    }

    static func opponent(_ name: String) -> ScorePill {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = cleaned.isEmpty ? "Opponent" : cleaned
        let configuration = ClubConfigurationStore.load()
        return ScorePill(
            label,
            style: ClubStyle.style(for: label, configuration: configuration),
            fixedWidth: ClubStyle.standardPillWidth(configuration: configuration)
        )
    }
}
