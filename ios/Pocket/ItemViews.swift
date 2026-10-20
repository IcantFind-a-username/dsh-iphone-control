import SwiftUI

struct ItemRow: View {
    let item: PocketItem
    var sessionId: String = ""

    var body: some View {
        switch item.k {
        case "u":
            UserBubble(item: item, sessionId: sessionId)
        case "t":
            ToolCard(item: item)
        case "n":
            NoticeChip(text: item.text ?? "")
        default:
            AssistantRow(item: item)
        }
    }
}

struct UserBubble: View {
    let item: PocketItem
    var sessionId: String = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 46)
            VStack(alignment: .leading, spacing: 7) {
                if let images = item.imgs, !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(images.enumerated()), id: \.offset) { _, ref in
                                if ref.attachmentId != nil {
                                    AttachmentImage(sessionId: sessionId, ref: ref, size: 168)
                                } else {
                                    Text("照片")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.92))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.18))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 260)
                }
                if let text = item.text, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 16))
                        .lineSpacing(3)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.bubble)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct PendingBubble: View {
    let text: String
    let imageCount: Int

    var body: some View {
        HStack {
            Spacer(minLength: 46)
            VStack(alignment: .leading, spacing: 6) {
                if imageCount > 0 {
                    Text("照片 ×\(imageCount)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                }
                Text(text)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.bubble)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(0.72)
        }
    }
}

struct AssistantRow: View {
    let item: PocketItem

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let think = item.think, !think.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ReasoningView(text: think, streaming: false, initiallyExpanded: false)
            }
            if let text = item.text, !text.isEmpty {
                MarkdownView(source: text)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = text
                            Haptics.tap()
                        } label: {
                            Label("复制全文", systemImage: "doc.on.doc")
                        }
                    }
            }
            if let usage = item.usage {
                UsageRow(usage: usage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UsageRow: View {
    let usage: PocketUsage

    var body: some View {
        HStack(spacing: 10) {
            if let output = usage.output, output > 0 {
                chip("\(output.formatted()) tok")
            }
            if let tps = usage.tps, tps > 0 {
                chip(String(format: "%.1f tok/s", tps))
            }
            if let rate = usage.cacheRate {
                chip("缓存 \(Int(rate.rounded()))%")
            }
            if let secs = usage.secs, secs > 0 {
                chip(String(format: "%.1fs", secs))
            }
        }
        .font(.system(size: 11.5, design: .rounded))
        .foregroundStyle(Theme.dim2)
        .padding(.top, 2)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 2.5)
            .background(Color.white.opacity(0.04), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
    }
}

struct LiveRow: View {
    let text: String
    let think: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if !think.isEmpty {
                ReasoningView(text: think, streaming: true, initiallyExpanded: false)
            }
            VStack(alignment: .leading, spacing: 4) {
                if text.isEmpty {
                    HStack(spacing: 8) {
                        Shimmer()
                        Text("正在思考")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim2)
                    }
                    .padding(.vertical, 4)
                } else {
                    MarkdownView(source: text)
                    Caret()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReasoningView: View {
    let text: String
    let streaming: Bool
    @State private var expanded: Bool

    init(text: String, streaming: Bool, initiallyExpanded: Bool = false) {
        self.text = text
        self.streaming = streaming
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    if streaming { Shimmer() }
                    Text(streaming ? "思考中" : "思考过程")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim2)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.dim2)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Text(text)
                .font(.system(size: 14))
                .lineSpacing(2.5)
                .foregroundStyle(Theme.dim)
                .lineLimit(expanded ? nil : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.leading, 11)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.lineStrong)
                .frame(width: 2)
        }
    }
}

struct ToolCard: View {
    let item: PocketItem
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 9) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(item.label ?? item.name ?? "工具")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(item.status == "err" ? Color(hex: 0xFFB3AD) : Theme.fgSoft)
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Rectangle()
                    .fill(Theme.line)
                    .frame(height: 1)
                ScrollView {
                    Text(item.result?.isEmpty == false ? (item.result ?? "") : "运行中…")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 240)
            }
        }
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line)
        )
    }

    private var statusColor: Color {
        switch item.status {
        case "run": return Theme.accent
        case "err": return Theme.err
        case "ok": return Theme.ok
        default: return Theme.dim2
        }
    }
}

struct NoticeChip: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 20)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.warn)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.warn.opacity(0.09))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.warn.opacity(0.24)))
            Spacer(minLength: 20)
        }
    }
}

struct EmptyStateView: View {
    @State private var float = false

    var body: some View {
        VStack(spacing: 12) {
            Image(uiImage: UIImage(named: "brand") ?? UIImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .strokeBorder(Theme.lineStrong, lineWidth: 1)
                )
                .offset(y: float ? -6 : 0)
                .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: float)
            Text("开始对话")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.fg)
                .padding(.top, 6)
            Text("在手机上继续你的 Harness 会话")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .onAppear { float = true }
    }
}
