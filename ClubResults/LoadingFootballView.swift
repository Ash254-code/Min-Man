import SwiftUI

struct LoadingFootballView: View {
    let title: String?
    var tint: Color = .orange
    var size: CGFloat = 26
    var font: Font = .body

    @State private var isSpinning = false

    init(
        _ title: String? = nil,
        tint: Color = .orange,
        size: CGFloat = 26,
        font: Font = .body
    ) {
        self.title = title
        self.tint = tint
        self.size = size
        self.font = font
    }

    var body: some View {
        Group {
            if let title, !title.isEmpty {
                HStack(spacing: 10) {
                    football
                    Text(title)
                        .font(font)
                }
            } else {
                football
            }
        }
        .onAppear {
            isSpinning = true
        }
    }

    private var football: some View {
        Image(systemName: "football.fill")
            .font(.system(size: size))
            .foregroundStyle(tint)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: isSpinning)
            .accessibilityHidden(title != nil)
    }
}
