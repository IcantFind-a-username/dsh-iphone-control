import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    let width: CGFloat
    var topInset: CGFloat
    var bottomInset: CGFloat
    var onClose: () -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            newChat
            list
            footer
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
        .clipped()
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.line)
                .frame(width: 1)
        }
        .ignoresSafeArea()
        .task { await model.loadSessions() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(uiImage: UIImage(named: "brand") ?? UIImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text("DeepSeek")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.fg)
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 28, height: 28)
                    .background(Theme.layer1, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, topInset + 8)
        .padding(.bottom, 12)
    }

    private var newChat: some View {
        Button {
            Haptics.tap()
            onClose()
            Task { await model.newSession() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12.5, weight: .medium))
                Text("新对话")
                    .font(.system(size: 13.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.fgSoft)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Theme.layer1, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.line)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(model.sessions) { session in
                    row(session)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func row(_ session: PocketSession) -> some View {
        let active = session.id == model.sessionId
        return Button {
            Haptics.tap()
            onClose()
            if !active { Task { await model.open(session.id) } }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(.system(size: 13, weight: active ? .medium : .regular))
                        .foregroundStyle(active ? Theme.fg : Theme.fgSoft)
                        .lineLimit(1)
                    Text(subtitle(session))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.dim2)
                }
                Spacer(minLength: 0)
                if session.running == true {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? Theme.layer2 : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            Button {
                Haptics.tap()
                onClose()
                onSettings()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12.5))
                    Text("设置")
                        .font(.system(size: 13))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, bottomInset + 8)
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
