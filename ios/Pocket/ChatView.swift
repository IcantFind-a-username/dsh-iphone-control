import SwiftUI
import PhotosUI
import UIKit

struct ChatView: View {
    @EnvironmentObject private var model: AppModel

    @State private var draft = ""
    @State private var images: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showSessions = false
    @State private var showSetup = false
    @State private var showWhale = ProcessInfo.processInfo.arguments.contains("-whale")
    @State private var showJump = false
    private let forceJump = ProcessInfo.processInfo.arguments.contains("-jump")
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                transcript
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { toolbarContent }
            .overlay(alignment: .bottomTrailing) {
                WhalePet(onOpenDetails: { showWhale = true })
                    .environmentObject(model)
                    .padding(.bottom, 76)
            }
            .overlay(alignment: .top) { errorBanner }
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    Text(toast)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.fgSoft)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Theme.layer2, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.lineStrong))
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                        .padding(.bottom, 96)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .sheet(isPresented: $showSessions) {
                SessionsSheet()
                    .environmentObject(model)
            }
            .sheet(isPresented: $showWhale) {
                WhaleSheet()
                    .environmentObject(model)
            }
            .sheet(isPresented: $showSetup) {
                NavigationStack { SetupView(mode: .settings).environmentObject(model) }
            }
            .onChange(of: pickerItems) { _, items in loadPhotos(items) }
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if model.hasMore {
                        Button {
                            Task { await model.loadOlder() }
                        } label: {
                            HStack(spacing: 6) {
                                if model.loadingOlder { ProgressView().controlSize(.small) }
                                Text(model.loadingOlder ? "正在加载…" : "加载更早的消息")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.accent.opacity(0.9))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 4)
                        }
                        .buttonStyle(.plain)
                    }

                    if model.items.isEmpty, !model.liveActive, model.pendingText == nil {
                        EmptyStateView()
                    }

                    ForEach(model.items) { item in
                        ItemRow(item: item, sessionId: model.sessionId ?? "")
                            .id(item.id)
                    }

                    if let pending = model.pendingText {
                        PendingBubble(text: pending, imageCount: model.pendingImages)
                            .id("pending")
                    }

                    if model.liveActive {
                        LiveRow(text: model.liveText, think: model.liveThink)
                            .id("live")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let distance = geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
                return distance > 240
            } action: { _, farFromBottom in
                withAnimation(.easeInOut(duration: 0.18)) { showJump = farFromBottom }
            }
            .overlay(alignment: .bottom) {
                if showJump || forceJump {
                    Button {
                        Haptics.tap()
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                        showJump = false
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                            Text("最新")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Theme.fgSoft)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(Theme.layer2, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.lineStrong))
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 80)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .onChange(of: model.sessionId) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if !images.isEmpty { previews }

            HStack(alignment: .bottom, spacing: 7) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.fgSoft)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.06), in: Circle())
                }

                TextField(model.running ? "插话…" : "发消息…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.fg)
                    .tint(Theme.accent)
                    .focused($inputFocused)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 2)

                if model.running, canSend {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 38, height: 38)
                            .background(Theme.primary, in: Circle())
                    }
                    .transition(.opacity)
                }

                if model.running {
                    Button {
                        Task { await model.stopTurn() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                    .transition(.opacity)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 38, height: 38)
                            .background(Theme.primary, in: Circle())
                            .opacity(canSend ? 1 : 0.32)
                    }
                    .disabled(!canSend)
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.lineStrong)
            )
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            LinearGradient(
                colors: [Theme.bg.opacity(0.0), Theme.bg.opacity(0.86), Theme.bg],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var previews: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.lineStrong)
                        )
                        .overlay(alignment: .topTrailing) {
                            Button {
                                images.remove(at: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Color.black.opacity(0.62), in: Circle())
                            }
                            .padding(3)
                        }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Haptics.tap()
                showSessions = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.fgSoft)
            }
        }

        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(model.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    StatusDot(kind: statusKind)
                    Text(statusText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 220)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await model.newSession() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.fgSoft)
            }
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = model.connectionError, !model.connected {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.warn)
                VStack(alignment: .leading, spacing: 3) {
                    Text("连不上电脑")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.fg)
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(3)
                    Text(model.baseURL)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.dim2)
                        .lineLimit(1)
                    Text("先在 Safari 里打开同一地址：能打开就是 App 权限问题（设置 → 隐私与安全性 → 本地网络 → 打开 Pocket），打不开就是手机没连上 Tailscale。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.dim2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 7) {
                    Button("重试") {
                        Task { await model.retry() }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    Button("设置") { showSetup = true }
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                    Button("Safari") {
                        if let url = URL(string: model.baseURL + "/?token=" + model.token) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.warn.opacity(0.28))
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var statusKind: StatusDot.Kind {
        if model.connectionError != nil, !model.connected { return .offline }
        if model.running { return .busy }
        return model.connected ? .online : .idle
    }

    private var statusText: String {
        if model.connectionError != nil, !model.connected { return "连接中断" }
        if model.running { return "正在回复…" }
        if model.connected {
            let name = (model.cwd as NSString).lastPathComponent
            return name.isEmpty ? "已连接" : name
        }
        return "连接中…"
    }

    // MARK: - Actions

    private func send() {
        guard canSend else { return }
        let text = draft
        let payload = images.compactMap { $0.jpegData(compressionQuality: 0.82) }
        draft = ""
        images = []
        pickerItems = []
        inputFocused = false
        Task { await model.send(text: text, images: payload, mode: model.running ? "steer" : "queue") }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image.downscaled(maxDimension: 1600))
                }
            }
            pickerItems = []
        }
    }
}

extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
