import SwiftUI
import SwiftData

@main
struct ClubResultsApp: App {

    @State private var showSplash = true
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    private var preferredScheme: ColorScheme? {
        switch AppAppearance(rawValue: appAppearance) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // ✅ FORCE premium background at the absolute root
                ClubTheme.bgGradient
                    .ignoresSafeArea()

                // subtle glow layers (same as AppScreenStyle)
                RadialGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.12), Color.clear]),
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 380
                )
                .ignoresSafeArea()

                RadialGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.08), Color.clear]),
                    center: .bottomLeading,
                    startRadius: 40,
                    endRadius: 420
                )
                .ignoresSafeArea()

                // Your app content
                ZStack {
                    ContentView()
                        .opacity(showSplash ? 0 : 1)

                    if showSplash {
                        SplashView()
                            .transition(.opacity)
                    }
                }
            }
            .preferredColorScheme(preferredScheme)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
        .modelContainer(for: [
            Player.self,
            Game.self,
            Grade.self,
            Contact.self,
            ReportRecipient.self,
            StaffMember.self,   // ✅ Staff list for pickers
            StaffDefault.self   // ✅ Default per grade + role
        ])
    }
}
