import SwiftUI

@main
struct PocketApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.paired {
                ChatView()
            } else {
                NavigationStack {
                    SetupView(mode: .onboarding)
                }
            }
        }
        .task { await model.startIfNeeded() }
    }
}
