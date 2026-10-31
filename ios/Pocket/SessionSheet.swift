import SwiftUI

/// One quiet sheet for everything that is not the conversation itself:
/// model, reasoning effort, permission preset and context headroom.
struct SessionSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var effort: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        modelSection
                        permissionSection
                        contextSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
                .refreshable {
                    await model.loadModels()
                    await model.loadPermissions()
                }
            }
            .navigationTitle("会话设置")
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
            .task {
                await model.loadModels()
                await model.loadPermissions()
                effort = model.modelCatalog?.current?.reasoningEffort
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
        .preferredColorScheme(.dark)
    }

    // MARK: model

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("模型")

            ForEach(model.modelCatalog?.groups ?? []) { group in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.models) { entry in
                        modelRow(group: group, entry: entry)
                        if entry.id != group.models.last?.id {
                            Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 14)
                        }
                    }
                }
                .background(Theme.layer1, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }

            if let reasoning = selectedReasoning, !reasoning.efforts.isEmpty {
                HStack(spacing: 6) {
                    ForEach(reasoning.efforts) { option in
                        let active = effort == option.id
                        Button {
                            effort = option.id
                            if let current = model.modelCatalog?.current {
                                Task {
                                    await model.selectModel(
                                        provider: current.provider,
                                        model: current.model,
                                        reasoningEffort: option.id
                                    )
                                }
                            }
                        } label: {
                            Text(option.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(active ? Theme.primaryText : Theme.dim)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(active ? Theme.primary : Theme.layer1, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
    }

    private var selectedReasoning: ModelReasoning? {
        guard let current = model.modelCatalog?.current else { return nil }
        return model.modelCatalog?.groups
            .first { $0.id == current.provider }?
            .models.first { $0.id == current.model }?
            .reasoning
    }

    private func modelRow(group: ModelGroup, entry: ModelEntry) -> some View {
        let selected = model.modelCatalog?.current?.provider == group.id
            && model.modelCatalog?.current?.model == entry.id
        return Button {
            effort = entry.reasoning?.defaultEffort
            Task {
                await model.selectModel(
                    provider: group.id,
                    model: entry.id,
                    reasoningEffort: entry.reasoning?.defaultEffort
                )
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .font(.system(size: 14.5))
                        .foregroundStyle(Theme.fg)
                    if let description = entry.description, !description.isEmpty, selected {
                        Text(description)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.dim2)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.ok)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: permission

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("权限")
            VStack(spacing: 0) {
                ForEach(model.permissions?.options ?? []) { option in
                    let selected = model.permissions?.current == option.value
                    Button {
                        Task { await model.selectPermission(option.value) }
                    } label: {
                        HStack(spacing: 10) {
                            Text(model.permissionLabel(option.value))
                                .font(.system(size: 14.5))
                                .foregroundStyle(Theme.fg)
                            Spacer(minLength: 0)
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.ok)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if option.id != model.permissions?.options.last?.id {
                        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 14)
                    }
                }
            }
            .background(Theme.layer1, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    // MARK: context

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("上下文")
            VStack(alignment: .leading, spacing: 8) {
                if let context = model.context, let ratio = context.ratio, let window = context.window, window > 0 {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.layer2)
                            Capsule()
                                .fill(ratio >= 0.9 ? Theme.err : ratio >= 0.75 ? Theme.warn : Theme.fgSoft)
                                .frame(width: max(4, proxy.size.width * ratio))
                        }
                    }
                    .frame(height: 4)
                    HStack {
                        Text("\(context.used ?? 0) / \(window)")
                        Spacer()
                        Text("\(Int((ratio * 100).rounded()))%")
                    }
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(Theme.dim2)
                    .monospacedDigit()
                } else {
                    Text("这个会话还没有上下文数据")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.dim2)
                }
            }
            .padding(14)
            .background(Theme.layer1, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(Theme.dim2)
    }
}
