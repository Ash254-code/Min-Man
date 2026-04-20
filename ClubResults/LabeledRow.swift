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
    var systemName: String = "circle.fill"
    var size: CGFloat = 16
    var columnWidth: CGFloat = 26

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.blue)
            .frame(width: columnWidth, alignment: .leading)
    }
}
