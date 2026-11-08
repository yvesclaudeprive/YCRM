import SwiftUI

@main
struct YCRMApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(\.locale, Locale(identifier: "fr_FR"))
        }
    }
}
