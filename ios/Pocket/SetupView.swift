import SwiftUI

struct SetupView: View {
    enum Mode {
        case onboarding
        case settings
    }

    let mode: Mode

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var base = ""
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if mode == .onboarding {
                        hero
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        label("服务器地址")
                        TextField("http://100.x.y.z:8931/pocket", text: $base)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(.system(size: 15, design: .monospaced))
                            .padding(13)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Theme.lineStrong)
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        label("配对令牌")
                        TextField("token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 14, design: .monospaced))
                            .padding(13)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Theme.lineStrong)
                            )
                    }

                    Button(action: connect) {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "正在连接…" : "连接")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(Theme.primaryText)
                    }
                    .disabled(busy)

                    if let error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.err)
                    }

                    hint

                    if mode == .settings {
                        Button(role: .destructive) {
                            model.unpair()
                            dismiss()
                        } label: {
                            Text("解除配对")
                                .font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(Theme.err)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(mode == .settings ? "设置" : "配对")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            base = model.baseURL
            token = model.token
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(uiImage: UIImage(named: "brand") ?? UIImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 6)
            Text("配对这台 Mac")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.fg)
            Text("Pocket 通过你自己的 Tailscale 网络连接电脑上的 DeepSeek Harness，令牌只保存在本机。")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.dim)
                .lineSpacing(2)
        }
        .padding(.bottom, 4)
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("怎么找令牌")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.fgSoft)
            Text("电脑上打开 ~/.dsh/pocket/state.json，复制其中的 token；服务器地址就是你在手机浏览器里能打开的那个 /pocket 地址。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim2)
                .lineSpacing(2)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line)
        )
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.dim)
    }

    private func connect() {
        busy = true
        error = nil
        Task {
            let ok = await model.pair(base: base, token: token)
            busy = false
            if ok {
                Haptics.done()
                if mode == .settings { dismiss() }
            } else {
                error = model.connectionError ?? "连接失败"
                Haptics.error()
            }
        }
    }
}
