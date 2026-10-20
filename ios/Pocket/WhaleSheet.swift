import SwiftUI

struct WhaleSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        if let whale = model.whale, whale.ok {
                            balanceCard(whale)
                            if let events = whale.events, !events.isEmpty {
                                recentCard(events)
                            }
                        } else if model.whaleLoading {
                            ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 40)
                        } else {
                            unavailable
                        }

                        footer
                    }
                    .padding(18)
                }
                .refreshable { await model.loadWhale() }
            }
            .navigationTitle("大肥鱼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                }
            }
            .task { await model.loadWhale() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(uiImage: UIImage(named: "pet") ?? UIImage())
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.lineStrong))
            VStack(alignment: .leading, spacing: 2) {
                Text("DeepSeek 余额")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                Text(model.whale?.date ?? "—")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.dim2)
            }
            Spacer()
        }
    }

    private func balanceCard(_ whale: WhaleResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.dim)
                Text(String(format: "%.2f", whale.balance ?? 0))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.fg)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 18) {
                stat("今日已用", String(format: "¥%.2f", whale.today ?? 0))
                stat("时段", whale.offPeak == true ? "谷时 · 5 折" : "峰时")
                Spacer(minLength: 0)
            }

            if whale.offPeak == true {
                Text("北京时间 00:30–08:30 为谷时，API 价格 5 折")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.layer1, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.line)
        )
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim2)
            Text(value)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.fgSoft)
                .monospacedDigit()
        }
    }

    private func recentCard(_ events: [WhaleEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近每轮消耗")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.dim)

            ForEach(events.suffix(8).reversed()) { event in
                HStack(spacing: 10) {
                    Text(time(event.ts))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.dim2)
                        .frame(width: 44, alignment: .leading)
                    Text(event.model ?? "—")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.fgSoft)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(Int((event.tokens ?? 0) / 1000))k tok")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.dim2)
                        .monospacedDigit()
                    Text(String(format: "¥%.3f", event.cost ?? 0))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.fgSoft)
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.layer1, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.line)
        )
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "fish")
                .font(.system(size: 30))
                .foregroundStyle(Theme.dim2)
            Text("还没有鲸鱼挂件的余额数据")
                .font(.system(size: 13))
                .foregroundStyle(Theme.dim)
            Text("在电脑上打开 DSH Web 界面，等右下角的大肥鱼取到一次余额即可。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.dim2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var footer: some View {
        Text("数据来自 dsh-whale-widget 的本地账本，\(model.whale?.peakLabel ?? "")")
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.dim2)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }

    private func time(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
