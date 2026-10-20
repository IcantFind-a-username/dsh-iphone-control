import SwiftUI

struct MarkdownBlock: Identifiable {
    enum Kind {
        case paragraph(String)
        case heading(String, Int)
        case code(String, String?)
        case bullets([String])
        case ordered([String])
        case quote(String)
    }

    let id: Int
    let kind: Kind
}

enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var list: (kind: Int, items: [String])?
        var counter = 0
        let lines = source.components(separatedBy: "\n")
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(MarkdownBlock(id: counter, kind: .paragraph(paragraph.joined(separator: "\n"))))
            counter += 1
            paragraph = []
        }

        func flushList() {
            guard let current = list, !current.items.isEmpty else {
                list = nil
                return
            }
            blocks.append(MarkdownBlock(id: counter, kind: current.kind == 0 ? .bullets(current.items) : .ordered(current.items)))
            counter += 1
            list = nil
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushList()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(MarkdownBlock(id: counter, kind: .code(code.joined(separator: "\n"), language.isEmpty ? nil : language)))
                counter += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                index += 1
                continue
            }

            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                let title = trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                if hashes <= 3, !title.isEmpty {
                    flushParagraph()
                    flushList()
                    blocks.append(MarkdownBlock(id: counter, kind: .heading(title, hashes)))
                    counter += 1
                    index += 1
                    continue
                }
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                if list == nil || list!.kind != 0 {
                    flushList()
                    list = (0, [])
                }
                list!.items.append(String(trimmed.dropFirst(2)))
                index += 1
                continue
            }

            if let match = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flushParagraph()
                if list == nil || list!.kind != 1 {
                    flushList()
                    list = (1, [])
                }
                list!.items.append(String(trimmed[match.upperBound...]))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                let quote = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(MarkdownBlock(id: counter, kind: .quote(quote)))
                counter += 1
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                flushList()
                index += 1
                continue
            }

            paragraph.append(line)
            index += 1
        }

        flushParagraph()
        flushList()
        return blocks
    }

    static func inline(_ text: String) -> AttributedString {
        guard var attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return AttributedString(text)
        }
        for run in attributed.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                attributed[run.range].font = .system(size: 14.5, design: .monospaced)
                attributed[run.range].foregroundColor = Color(hex: 0xC9D2FF)
            }
        }
        return attributed
    }
}

struct MarkdownView: View {
    let source: String
    var size: CGFloat = 16

    var body: some View {
        let blocks = MarkdownParser.parse(source)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block.kind {
                case .paragraph(let text):
                    Text(MarkdownParser.inline(text))
                        .font(.system(size: size))
                        .lineSpacing(3.5)
                        .foregroundStyle(Theme.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                case .heading(let text, let level):
                    Text(MarkdownParser.inline(text))
                        .font(.system(size: level == 1 ? 19 : level == 2 ? 17.5 : 16.5, weight: .semibold))
                        .foregroundStyle(Theme.fg)
                        .textSelection(.enabled)
                        .padding(.top, 2)

                case .code(let code, let language):
                    CodeBlockView(code: code, language: language)

                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").font(.system(size: size)).foregroundStyle(Theme.dim)
                                Text(MarkdownParser.inline(item))
                                    .font(.system(size: size))
                                    .lineSpacing(3)
                                    .foregroundStyle(Theme.fg)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                case .ordered(let items):
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(offset + 1).").font(.system(size: size - 1, design: .rounded)).foregroundStyle(Theme.dim)
                                Text(MarkdownParser.inline(item))
                                    .font(.system(size: size))
                                    .lineSpacing(3)
                                    .foregroundStyle(Theme.fg)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                case .quote(let text):
                    Text(MarkdownParser.inline(text))
                        .font(.system(size: size - 1.5))
                        .italic()
                        .foregroundStyle(Theme.dim)
                        .padding(.leading, 11)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Theme.lineStrong).frame(width: 2)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text((language ?? "").uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Theme.dim2)
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = code
                    Haptics.tap()
                    withAnimation(.easeOut(duration: 0.15)) { copied = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        withAnimation(.easeOut(duration: 0.15)) { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                        Text(copied ? "已复制" : "复制")
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(copied ? Theme.ok : Theme.dim2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xD7DBE6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.codeBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line)
        )
    }
}
