import SwiftUI

struct OpponentBadge: View {
    let opponent: String
    let fixedWidth: CGFloat?

    init(opponent: String, fixedWidth: CGFloat? = nil) {
        self.opponent = opponent
        self.fixedWidth = fixedWidth
    }

    var body: some View {
        let configuration = ClubConfigurationStore.load()
        let style = ClubStyle.style(for: opponent, configuration: configuration)
        let resolvedWidth = fixedWidth ?? ClubStyle.standardPillWidth(configuration: configuration)

        Text(opponent)
            .font(.subheadline)
            .fontWeight(.semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: resolvedWidth, alignment: .center)
            .background(
                Capsule(style: .continuous)
                    .fill(style.background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(style.border.opacity(0.95), lineWidth: 1.5)
            )
            .foregroundStyle(style.text)
            .accessibilityLabel(Text("Opponent: \(opponent)"))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        OpponentBadge(opponent: "RSMU", fixedWidth: 180)
        OpponentBadge(opponent: "BSR")
        OpponentBadge(opponent: "Very Long Opponent Name That Might Truncate", fixedWidth: 220)
    }
    .padding()
}
