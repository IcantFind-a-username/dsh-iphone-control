import SwiftUI

struct SessionsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                List {
                    ForEach(model.sessions) { session in
                        Button {
                            Haptics.tap()
                            Task {
                                await model.open(session.id)
                                dismiss()
                            }
                        } label: {
                            row(session)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.line)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SetupView(mode: .settings)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                }
            }
            .task { await model.loadSessions() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private func row(_ session: PocketSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.system(size: 15, weight: session.id == model.sessionId ? .semibold : .regular))
                    .foregroundStyle(session.id == model.sessionId ? Color(hex: 0xA9B8FF) : Theme.fg)
                    .lineLimit(1)
                Text(subtitle(session))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.dim2)
            }
            Spacer(minLength: 0)
            if session.running == true {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: Theme.accent.opacity(0.8), radius: 5)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func subtitle(_ session: PocketSession) -> String {
        if session.running == true { return "正在回复…" }
        guard let date = session.updated else { return session.cwd ?? "" }
        return Self.relative.localizedString(for: date, relativeTo: Date())
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()
}
