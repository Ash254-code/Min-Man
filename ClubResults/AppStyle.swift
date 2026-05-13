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
    static let background = Color(uiColor: UIColor { trait in
        guard trait.userInterfaceStyle != .dark else {
            return .systemBackground
        }

        let base = UIColor.systemGroupedBackground.resolvedColor(with: trait)
        let navy = UIColor(red: 0.05, green: 0.15, blue: 0.35, alpha: 1)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var navyRed: CGFloat = 0
        var navyGreen: CGFloat = 0
        var navyBlue: CGFloat = 0
        var navyAlpha: CGFloat = 0

        guard base.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              navy.getRed(&navyRed, green: &navyGreen, blue: &navyBlue, alpha: &navyAlpha) else {
            return base
        }

        let navyBlend: CGFloat = 0.026
        let baseBlend = 1 - navyBlend
        return UIColor(
            red: (red * baseBlend) + (navyRed * navyBlend),
            green: (green * baseBlend) + (navyGreen * navyBlend),
            blue: (blue * baseBlend) + (navyBlue * navyBlend),
            alpha: alpha
        )
    })
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

    @ViewBuilder
    func iPhoneTransparentTopChrome() -> some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            self
                .toolbarBackground(.hidden, for: .navigationBar)
                .background(ClubTheme.bgGradient.ignoresSafeArea())
        } else {
            self
        }
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


extension Color {
    /// Matches Apple's standard iOS blue accent.
    static let appleBlue = Color(uiColor: .systemBlue)
}
