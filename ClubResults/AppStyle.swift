import SwiftUI
import UIKit

enum PickerSheetPresentation {
    private static var contextScreenHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .screen
            .bounds
            .height
            ?? 844
    }

    static func preferredHeight(
        optionCount: Int,
        rowHeight: CGFloat,
        chromeHeight: CGFloat,
        minVisibleRows: Int = 3,
        isCompactLayout: Bool
    ) -> CGFloat {
        let screenHeight = contextScreenHeight
        let topAndBottomMargin: CGFloat = isCompactLayout ? 20 : 56
        let maxHeight = max(
            chromeHeight + (rowHeight * CGFloat(minVisibleRows)),
            screenHeight - topAndBottomMargin
        )

        let minHeight = chromeHeight + (rowHeight * CGFloat(minVisibleRows))
        let desiredHeight = chromeHeight + (rowHeight * CGFloat(max(optionCount, 0)))

        return min(max(desiredHeight, minHeight), maxHeight)
    }

    static func expandedDetent(isCompactLayout: Bool) -> PresentationDetent {
        isCompactLayout ? .large : .fraction(0.98)
    }
}

enum AppStyle {
    static let background = Color("AppBackground")   // your global background
    static let card = Color(.systemBackground)       // keeps cards readable in light/dark
}

struct AppScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)       // makes Lists stop painting their own bg
            .background(AppStyle.background)
    }
}

extension View {
    func appScreenStyle() -> some View {
        modifier(AppScreenBackground())
    }

    func appPopupStyle() -> some View {
        modifier(AppPopupPresentation())
    }
}

private struct AppPopupPresentation: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .presentationDetents(horizontalSizeClass == .compact ? [.fraction(0.96), .large] : [.fraction(0.9), .fraction(0.98), .large])
                .presentationSizing(.page)
                .presentationDragIndicator(.visible)
        } else {
            content
                .presentationDetents(horizontalSizeClass == .compact ? [.fraction(0.96), .large] : [.fraction(0.9), .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct AppPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.blue) // <- change once if you want (or Theme.primary)
            )
            .lineLimit(1)
    }
}
