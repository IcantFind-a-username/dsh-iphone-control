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
    @State private var dragOffset: CGFloat = 0
    @State private var showSetup = false

    var body: some View {
        GeometryReader { proxy in
            let width = min(330, proxy.size.width * 0.84)
            ZStack(alignment: .leading) {
                content

                if model.paired {
                    if model.sidebarOpen {
                        Color.black.opacity(0.42)
                            .ignoresSafeArea()
                            .onTapGesture { close() }
                            .transition(.opacity)
                    }

                    SidebarView(
                        width: width,
                        topInset: proxy.safeAreaInsets.top,
                        bottomInset: proxy.safeAreaInsets.bottom,
                        onClose: close,
                        onSettings: { showSetup = true }
                    )
                        .offset(x: sidebarX(width))
                        .shadow(color: .black.opacity(model.sidebarOpen ? 0.55 : 0), radius: 28, x: 12)
                }
            }
            .simultaneousGesture(drawerGesture(width))
        }
        .sheet(isPresented: $showSetup) {
            NavigationStack {
                SetupView(mode: .settings).environmentObject(model)
            }
        }
        .task {
            await model.startIfNeeded()
            if ProcessInfo.processInfo.arguments.contains("-sidebar") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    model.sidebarOpen = true
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.paired {
            ChatView()
        } else {
            NavigationStack {
                SetupView(mode: .onboarding)
            }
        }
    }

    private func sidebarX(_ width: CGFloat) -> CGFloat {
        model.sidebarOpen ? dragOffset : -width + dragOffset
    }

    private func open() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            model.sidebarOpen = true
            dragOffset = 0
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            model.sidebarOpen = false
            dragOffset = 0
        }
    }

    private func reset() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            dragOffset = 0
        }
    }

    private func drawerGesture(_ width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let horizontal = abs(value.translation.width) > abs(value.translation.height)
                guard horizontal else { return }
                if model.sidebarOpen {
                    guard value.startLocation.x < width + 24 else { return }
                    dragOffset = min(0, value.translation.width)
                } else {
                    guard value.startLocation.x < 30 else { return }
                    dragOffset = max(0, min(width, value.translation.width))
                }
            }
            .onEnded { value in
                let horizontal = abs(value.translation.width) > abs(value.translation.height)
                guard horizontal else { reset(); return }
                if model.sidebarOpen {
                    if dragOffset < -width * 0.22 || value.predictedEndTranslation.width < -width * 0.45 {
                        close()
                    } else {
                        reset()
                    }
                } else {
                    if dragOffset > width * 0.28 || value.predictedEndTranslation.width > width * 0.45 {
                        open()
                    } else {
                        reset()
                    }
                }
            }
    }
}
