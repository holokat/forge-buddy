import SwiftUI

@main
struct ForgeBuddyApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(model.appearance.colorScheme)
                .onOpenURL { url in
                    model.handlePairingURL(url)
                }
        }
    }
}
