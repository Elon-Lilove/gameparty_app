import SwiftUI
import PartyGames

@main
struct PartyGamesApp: App {
    @State private var isShowingLaunchScreen = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView(isLaunchScreenVisible: $isShowingLaunchScreen)

                if isShowingLaunchScreen {
                    AppLaunchOverlay()
                        .allowsHitTesting(false)
                        .zIndex(1)
                }
            }
            .animation(nil, value: isShowingLaunchScreen)
        }
    }
}

private struct AppLaunchOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white
                    .ignoresSafeArea()

                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width * 0.18, height: proxy.size.width * 0.18)
            }
        }
        .ignoresSafeArea()
    }
}
