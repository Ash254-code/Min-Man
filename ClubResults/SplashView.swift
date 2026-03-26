import SwiftUI

struct SplashView: View {

    // Club colours
    private let clubBlue = Color(red: 0.05, green: 0.15, blue: 0.35)

    @State private var fadeIn = false
    @State private var pulse = false

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    var body: some View {
        ZStack {
            clubBlue
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("club_logo") // must match asset name
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180)
                    .scaleEffect(pulse ? 1.05 : 1.0)
                    .opacity(fadeIn ? 1 : 0)

                Text(versionString)
                    .font(.footnote)
                    .foregroundStyle(.yellow.opacity(0.9))
                    .opacity(fadeIn ? 1 : 0)
                    .padding(.top, 6)
            }
            .padding(.bottom, 20)
        }
        .onAppear {
            // Fade in once
            withAnimation(.easeOut(duration: 0.5)) {
                fadeIn = true
            }
            // Gentle pulse forever while splash is visible
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
