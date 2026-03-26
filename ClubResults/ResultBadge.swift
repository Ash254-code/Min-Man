import SwiftUI

struct ResultBadge: View {
    let ourScore: Int
    let theirScore: Int
    
    private var resultLabel: String {
        if ourScore > theirScore {
            return "Win"
        } else if ourScore < theirScore {
            return "Loss"
        } else {
            return "Draw"
        }
    }
    
    private var backgroundColor: Color {
        if ourScore > theirScore {
            return Color.green.opacity(0.2)
        } else if ourScore < theirScore {
            return Color.red.opacity(0.2)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
    
    private var foregroundColor: Color {
        if ourScore > theirScore {
            return Color.green
        } else if ourScore < theirScore {
            return Color.red
        } else {
            return Color.gray
        }
    }
    
    var body: some View {
        Text(resultLabel)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundColor(foregroundColor)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
            .fixedSize()
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    VStack(spacing: 10) {
        ResultBadge(ourScore: 3, theirScore: 1)
        ResultBadge(ourScore: 2, theirScore: 2)
        ResultBadge(ourScore: 0, theirScore: 4)
    }
    .padding()
}
