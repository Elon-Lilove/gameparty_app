import SwiftUI
import UIKit
import PartyGames

@main
struct PartyGamesApp: App {
    @State private var isShowingLaunchScreen = true

    var body: some Scene {
        WindowGroup {
            Group {
                if isShowingLaunchScreen {
                    LaunchScreenView()
                        .ignoresSafeArea()
                        .task {
                            // Leave enough headroom for the system-to-app handoff so the
                            // launch artwork remains visibly static for at least 1.5 seconds.
                            try? await Task.sleep(for: .seconds(2.5))

                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                isShowingLaunchScreen = false
                            }
                        }
                } else {
                    RootView()
                }
            }
            .animation(nil, value: isShowingLaunchScreen)
        }
    }
}

private struct LaunchScreenView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        guard let viewController = UIStoryboard(
            name: "LaunchScreen",
            bundle: .main
        ).instantiateInitialViewController() else {
            preconditionFailure("LaunchScreen.storyboard must have an initial view controller")
        }

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}
