import SwiftUI

struct ModelSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var effort: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let catalog = model.modelCatalog {
                            ForEach(catalog.groups) { group in
                                groupView(group)
                            }
                            ForEach(catalog.failures ?? [], id: \.id) { failure in
                                Text("\(failure.name)：\(failure.message)")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.err)
                            }
                        } else if model.modelLoading {
                            ProgressView()
                                .tint(Theme.fgSoft)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            Text("没有可用模型")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.dim)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                    }
                    .padding(18)
                }
                .refreshable { await model.loadModels() }
            }
            .navigationTitle("模型")
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
                effort = model.modelCatalog?.current?.reasoningEffort
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private func groupView(_ group: ModelGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.name.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.dim2)

            VStack(spacing: 0) {
                ForEach(group.models) { entry in
                    row(group: group, entry: entry)
                    if entry.id != group.models.last?.id {
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }
                }
            }
            .background(Theme.layer1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.line)
            )
        }
    }

    private func row(group: ModelGroup, entry: ModelEntry) -> some View {
        let selected = model.modelCatalog?.current?.provider == group.id
            && model.modelCatalog?.current?.model == entry.id

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                effort = entry.reasoning?.defaultEffort ?? effort
                Task {
                    await model.selectModel(
                        provider: group.id,
                        model: entry.id,
                        reasoningEffort: entry.reasoning?.defaultEffort
                    )
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundStyle(Theme.fg)
                        if let description = entry.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.dim2)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ok)
                            .padding(.top, 3)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if selected, let reasoning = entry.reasoning, !reasoning.efforts.isEmpty {
                HStack(spacing: 7) {
                    ForEach(reasoning.efforts) { option in
                        let active = effort == option.id
                        Button {
                            effort = option.id
                            Task {
                                await model.selectModel(
                                    provider: group.id,
                                    model: entry.id,
                                    reasoningEffort: option.id
                                )
                            }
                        } label: {
                            Text(option.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(active ? Theme.primaryText : Theme.fgSoft)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(active ? Theme.primary : Theme.layer2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
    }
}
