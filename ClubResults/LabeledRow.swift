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
