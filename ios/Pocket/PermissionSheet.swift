import SwiftUI

struct PermissionSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("这个会话允许 Agent 做什么")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim2)
                            .padding(.bottom, 4)

                        ForEach(model.permissions?.options ?? []) { option in
                            row(option)
                        }

                        Text("切换只影响当前会话；执行中的工具不会改变。")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim2)
                            .padding(.top, 8)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("权限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                }
            }
            .task { await model.loadPermissions() }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private func row(_ option: PermissionOption) -> some View {
        let selected = model.permissions?.current == option.value
        return Button {
            Task {
                await model.selectPermission(option.value)
                dismiss()
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon(option.value))
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Theme.fg : Theme.dim)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.permissionLabel(option.value))
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.fg)
                    Text(detail(option.value))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.dim2)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ok)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.layer1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Theme.lineEmphasis : Theme.line)
            )
        }
        .buttonStyle(.plain)
    }

    private func icon(_ value: String) -> String {
        switch value {
        case "read-only": return "eye"
        case "workspace-write": return "folder.badge.gearshape"
        case "danger-full-access": return "exclamationmark.shield"
        default: return "slider.horizontal.3"
        }
    }

    private func detail(_ value: String) -> String {
        switch value {
        case "read-only": return "只能读文件，不能写、不能跑命令"
        case "workspace-write": return "只能改当前工作区，越界操作需要确认"
        case "danger-full-access": return "不受沙箱限制，谨慎使用"
        default: return ""
        }
    }
}
