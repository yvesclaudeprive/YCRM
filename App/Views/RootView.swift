import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        if session.hasToken {
            ActivityListView()
        } else {
            NavigationStack {
                SettingsView()
            }
        }
    }
}
