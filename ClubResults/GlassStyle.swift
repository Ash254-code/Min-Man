import SwiftUI
import UIKit

// MARK: - Club Theme

enum ClubTheme {
    static let navy = Color(red: 0.05, green: 0.15, blue: 0.35)
    static let yellow = Color(red: 1.0, green: 0.82, blue: 0.0)

    // Shared main-card surface to match Settings-style grouped grey.
    static let cardFill = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardOverlay = Color.white.opacity(0.03)
    static let cardStroke = Color.white.opacity(0.14)

    // Sub-cards remain slightly lighter than main cards.
    static let subCardFill = Color.white.opacity(0.08)
    static let subCardStroke = Color.white.opacity(0.14)

    private static var clubPrimaryUIColor: UIColor {
        let configuration = ClubConfigurationStore.load()
        return UIColor(Color(hex: configuration.clubTeam.primaryColorHex, fallback: .blue))
    }

    private static func adjusted(_ color: UIColor, add: CGFloat = 0, multiply: CGFloat = 1) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return color
        }

        let r = min(max((red * multiply) + add, 0), 1)
        let g = min(max((green * multiply) + add, 0), 1)
        let b = min(max((blue * multiply) + add, 0), 1)

        return UIColor(red: r, green: g, blue: b, alpha: alpha)
    }

    private static var bgTop: Color {
        Color(uiColor: UIColor { trait in
            let base = clubPrimaryUIColor
            if trait.userInterfaceStyle == .dark {
                return adjusted(base, add: -0.04, multiply: 0.46)
            }
            return adjusted(base, add: 0.08, multiply: 0.16)
        })
    }

    private static var bgMiddle: Color {
        Color(uiColor: UIColor { trait in
            let base = clubPrimaryUIColor
            if trait.userInterfaceStyle == .dark {
                return adjusted(base, add: -0.02, multiply: 0.52)
            }
            return adjusted(base, add: 0.11, multiply: 0.18)
        })
    }

    private static var bgBottom: Color {
        Color(uiColor: UIColor { trait in
            let base = clubPrimaryUIColor
            if trait.userInterfaceStyle == .dark {
                return adjusted(base, add: 0.01, multiply: 0.58)
            }
            return adjusted(base, add: 0.15, multiply: 0.20)
        })
    }

    static var bgGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: bgTop, location: 0.0),
                .init(color: bgMiddle, location: 0.48),
                .init(color: bgBottom, location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - App Background Modifier

struct AppScreenStyle: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            ClubTheme.bgGradient
                .ignoresSafeArea()

            // subtle glow layers (premium depth)
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.06),
                    Color.clear
                ]),
                center: .bottomTrailing,
                startRadius: 36,
                endRadius: 340
            )
            .ignoresSafeArea()

            RadialGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.02),
                    Color.clear
                ]),
                center: .topLeading,
                startRadius: 40,
                endRadius: 440
            )
            .ignoresSafeArea()

            content
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        }
    }
}

struct ClubGlassSurfaceStyle: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ClubTheme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(ClubTheme.cardOverlay)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ClubTheme.cardStroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }
}

extension View {
    /// Apply the global app background & glow layers.
    func clubGlassBackground() -> some View { modifier(AppScreenStyle()) }

    /// Shared modern glass surface for cards and panels.
    func clubGlassSurface(cornerRadius: CGFloat = 22) -> some View {
        modifier(ClubGlassSurfaceStyle(cornerRadius: cornerRadius))
    }
}

// MARK: - Premium Glass Card

struct PremiumGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 26
    var contentPadding: CGFloat = 8// ✅ change THIS to control height everywhere

    func body(content: Content) -> some View {
        content
            .padding(contentPadding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ClubTheme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(ClubTheme.cardOverlay)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ClubTheme.cardStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
    }
}

extension View {
    func premiumGlassCard(cornerRadius: CGFloat = 2, contentPadding: CGFloat = 8) -> some View {
        modifier(PremiumGlassCard(cornerRadius: cornerRadius, contentPadding: contentPadding))
    }
}


extension View {
    /// Premium glass card styling (blur + highlight + floating shadow)
    func premiumGlassCard(cornerRadius: CGFloat = 26) -> some View {
        modifier(PremiumGlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Premium Glass Pill

struct GlassPill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ClubTheme.yellow)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(Capsule().fill(ClubTheme.navy.opacity(0.55)))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.20), radius: 10, y: 6)
    }
}

extension View {
    func glassPill() -> some View { modifier(GlassPill()) }
}
