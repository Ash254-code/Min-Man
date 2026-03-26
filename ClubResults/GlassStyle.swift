import SwiftUI

// MARK: - Club Theme

enum ClubTheme {
    static let navy = Color(red: 0.05, green: 0.15, blue: 0.35)
    static let yellow = Color(red: 1.0, green: 0.82, blue: 0.0)

    // App background gradient (premium)
    static let bgGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(red: 0.16, green: 0.30, blue: 0.95),
            Color(red: 0.12, green: 0.22, blue: 0.75),
            Color(red: 0.07, green: 0.14, blue: 0.45)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
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
                    Color.white.opacity(0.12),
                    Color.clear
                ]),
                center: .topTrailing,
                startRadius: 40,
                endRadius: 380
            )
            .ignoresSafeArea()

            RadialGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.08),
                    Color.clear
                ]),
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 420
            )
            .ignoresSafeArea()

            content
        }
    }
}

extension View {
    /// Apply the global app background & glow layers.
    func clubGlassBackground() -> some View { modifier(AppScreenStyle()) }

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
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
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
