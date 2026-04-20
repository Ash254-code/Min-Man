import SwiftUI

struct LabeledRow<Right: View>: View {
    let title: String
    @ViewBuilder var right: () -> Right

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            right()
        }
    }
}

struct StandardListIcon: View {
    var systemName: String = "person.3.fill"
    var size: CGFloat = 16
    var columnWidth: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.blue.opacity(0.14))
                .frame(width: 24, height: 24)

            Image(systemName: systemName)
                .font(.system(size: size - 3, weight: .semibold))
                .foregroundStyle(.blue)
        }
        .frame(width: columnWidth, alignment: .leading)
    }
}
