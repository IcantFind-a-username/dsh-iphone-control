import SwiftUI

struct ItemRow: View {
    let item: PocketItem
    var sessionId: String = ""

    var body: some View {
        switch item.k {
        case "u":
            UserBubble(item: item, sessionId: sessionId)
        case "t":
            if let ask = item.ask {
                AskCard(item: item, ask: ask)
            } else {
                ToolRow(item: item)
            }
        case "n":
            NoticeLine(text: item.text ?? "")
        default:
            AssistantRow(item: item)
        }
    }
}

// MARK: - User

struct UserBubble: View {
    let item: PocketItem
    var sessionId: String = ""

    var body: some View {
        HStack {
            Spacer(minLength: 56)
            VStack(alignment: .leading, spacing: 8) {
                if let images = item.imgs, !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(images.enumerated()), id: \.offset) { _, ref in
                                if ref.attachmentId != nil {
                                    AttachmentImage(sessionId: sessionId, ref: ref, size: 170)
                                } else {
                                    Text("照片")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.85))
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
                        .foregroundStyle(Theme.fg)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.layer2)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct PendingBubble: View {
    let text: String
    let imageCount: Int

    var body: some View {
        HStack {
            Spacer(minLength: 56)
            VStack(alignment: .leading, spacing: 6) {
                if imageCount > 0 {
                    Text("照片 ×\(imageCount)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.dim)
                }
                Text(text)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.fg)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.layer2)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(0.6)
        }
    }
}

// MARK: - Assistant

struct AssistantRow: View {
    let item: PocketItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                UsageLine(usage: usage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UsageLine: View {
    let usage: PocketUsage

    var body: some View {
        HStack(spacing: 6) {
            if let output = usage.output, output > 0 {
                Text("\(output.formatted()) tok")
            }
            if let tps = usage.tps, tps > 0 {
                Text("· \(String(format: "%.0f", tps)) tok/s")
            }
            if let rate = usage.cacheRate {
                Text("· 缓存 \(Int(rate.rounded()))%")
            }
            if let secs = usage.secs, secs > 0 {
                Text("· \(String(format: "%.1f", secs))s")
            }
        }
        .font(.system(size: 11, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(Theme.dim2)
        .padding(.top, 2)
    }
}

struct LiveRow: View {
    let text: String
    let think: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    if streaming { Shimmer() }
                    Text(streaming ? "思考中" : "思考")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.dim2)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.dim2)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Text(text)
                .font(.system(size: 13.5))
                .lineSpacing(2.5)
                .foregroundStyle(Theme.dim)
                .lineLimit(expanded ? nil : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Tools

struct ToolRow: View {
    let item: PocketItem
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(item.label ?? item.name ?? "工具")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.dim)
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.dim2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(Theme.dim2.opacity(0.8))
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ScrollView {
                    Text(item.result?.isEmpty == false ? (item.result ?? "") : "运行中…")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
                .background(Theme.layer1, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
        }
    }

    private var statusColor: Color {
        switch item.status {
        case "run": return Theme.accent
        case "err": return Theme.err
        case "ok": return Theme.ok.opacity(0.8)
        default: return Theme.dim2
        }
    }
}

struct NoticeLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.warn.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
    }
}

// MARK: - Ask

struct AskCard: View {
    let item: PocketItem
    let ask: AskPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12))
                Text("需要你回答")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                if item.status == "run" {
                    Text("等待中")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warn)
                }
            }
            .foregroundStyle(Theme.dim)

            ForEach(Array(ask.questions.enumerated()), id: \.offset) { _, question in
                VStack(alignment: .leading, spacing: 8) {
                    if !question.header.isEmpty {
                        Text(question.header)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.dim2)
                    }
                    Text(question.question)
                        .font(.system(size: 15))
                        .lineSpacing(2)
                        .foregroundStyle(Theme.fg)
                    VStack(spacing: 1) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: question.multiSelect ? "square" : "circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.dim2)
                                    .padding(.top, 3)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(option.label)
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(Theme.fgSoft)
                                    if !option.description.isEmpty {
                                        Text(option.description)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Theme.dim2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Theme.layer1)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            if item.status == "run" {
                Text("在电脑上选择后会自动更新")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim2)
            } else if let result = item.result, !result.isEmpty {
                Text(result)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.dim2)
                    .lineLimit(4)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Empty

struct EmptyStateView: View {
    @State private var float = false

    var body: some View {
        VStack(spacing: 10) {
            Image(uiImage: UIImage(named: "brand") ?? UIImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .offset(y: float ? -4 : 0)
                .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: float)
            Text("开始对话")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.fg)
            Text("在手机上继续你的 Harness 会话")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.dim2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
        .onAppear { float = true }
    }
}

/// Consecutive tool calls collapse into one quiet line, the way a terminal-style
/// agent would summarise "ran 3 commands, viewed 1 image" before you expand it.
struct ActivityRow: View {
    let items: [PocketItem]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(hasError ? Theme.err : Theme.dim2)
                        .frame(width: 5, height: 5)
                    Text(summary)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(Theme.dim2.opacity(0.7))
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        ToolRow(item: item)
                    }
                }
                .padding(.leading, 13)
                .padding(.top, 2)
            }
        }
    }

    private var hasError: Bool {
        items.contains { $0.status == "err" }
    }

    private var summary: String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for item in items {
            let key = item.label ?? item.name ?? "工具"
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        let parts = order.map { key in
            let count = counts[key] ?? 1
            return count > 1 ? "\(key) ×\(count)" : key
        }
        return parts.joined(separator: " · ")
    }
}
