import SwiftUI
import BiumCore

struct ScanView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !model.unreadable.isEmpty { PermissionNotice(model: model) }
                    if let report = model.report { CleanSummary(report: report, strings: model.strings) }

                    ForEach(SafetyLevel.allCases, id: \.self) { level in
                        let groups = model.groups(at: level)
                        if !groups.isEmpty {
                            SafetySection(model: model, level: level, groups: groups)
                        }
                    }

                    // A scan walks the whole home directory, so without this the
                    // window sits empty for tens of seconds with only a small
                    // toolbar spinner to say anything is happening.
                    if model.groups.isEmpty && model.isBusy {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.large)
                            Text(model.strings.scanning).font(.callout.weight(.medium))
                            Text(model.progress ?? "")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: 460)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                    }

                    if model.groups.isEmpty && !model.isBusy {
                        ContentUnavailableView(
                            model.strings.nothingFound,
                            systemImage: "sparkles",
                            description: Text(model.strings.outsideHomeNote)
                        )
                        .padding(.top, 60)
                    }
                }
                .padding(20)
            }
            Divider()
            Footer(model: model)
        }
        .navigationTitle(model.strings.scanResults)
        .confirmationDialog(
            model.permanentDelete
                ? model.strings.confirmTitlePermanent(formatBytes(model.selectedBytes))
                : model.strings.confirmTitle(formatBytes(model.selectedBytes)),
            isPresented: $model.confirming,
            titleVisibility: .visible
        ) {
            Button(
                model.permanentDelete ? model.strings.deletePermanently : model.strings.moveToTrash,
                role: model.permanentDelete ? .destructive : nil
            ) { Task { await model.clean() } }
            Button(model.strings.cancel, role: .cancel) {}
        } message: {
            Text(model.strings.guardNote)
        }
    }
}

private struct SafetySection: View {
    @Bindable var model: AppModel
    let level: SafetyLevel
    let groups: [RuleGroup]

    private var isOpen: Bool { model.expanded.contains(level) }
    private var allSelected: Bool { groups.allSatisfy { model.selected.contains($0.ruleID) } }
    private var total: Int64 { groups.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isOpen {
                Divider()
                ForEach(Array(groups.enumerated()), id: \.element.ruleID) { index, group in
                    if index > 0 { Divider().padding(.leading, 44) }
                    GroupRow(model: model, group: group)
                }
            }
        }
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                if isOpen { model.expanded.remove(level) } else { model.expanded.insert(level) }
            } label: {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 12)
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(get: { allSelected }, set: { _ in model.toggleAll(at: level) }))
                .labelsHidden().toggleStyle(.checkbox)

            Label(level.label, systemImage: level.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(level.tint, in: .rect(cornerRadius: 5))

            Text(level.headline).font(.callout.weight(.semibold))
            Text(level.blurb).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(formatBytes(total)).font(.callout.weight(.bold)).monospacedDigit()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

private struct GroupRow: View {
    @Bindable var model: AppModel
    let group: RuleGroup
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { model.selected.contains(group.ruleID) },
                    set: { _ in model.toggle(group) }
                ))
                .labelsHidden().toggleStyle(.checkbox)

                if group.isAction {
                    Image(systemName: "play.circle").foregroundStyle(.secondary)
                        .help(t("Runs the owning tool's own cleanup command.",
                                "해당 도구의 정리 명령을 실행합니다."))
                }

                Text(group.title).font(.callout)
                Text(group.ruleID)
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.quaternary, in: .rect(cornerRadius: 4))

                Spacer()
                Text(model.strings.itemCount(group.items.count))
                    .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                Text(formatBytes(group.bytes))
                    .font(.callout.weight(.semibold)).monospacedDigit()
                    .frame(width: 84, alignment: .trailing)
                Button { showDetail.toggle() } label: {
                    Image(systemName: showDetail ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .contentShape(.rect)
            .onTapGesture { model.toggle(group) }

            if showDetail {
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(group.items.prefix(12), id: \.path) { item in
                        HStack(spacing: 8) {
                            Text(displayPath(item.path)).font(.caption2.monospaced())
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if let note = item.note {
                                Text(note).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text(formatBytes(item.bytes))
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    if group.items.count > 12 {
                        Text(t("and \(group.items.count - 12) more",
                               "외 \(group.items.count - 12)개"))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 44).padding(.bottom, 12)
            }
        }
    }
}

private struct PermissionNotice: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "lock.fill").foregroundStyle(Palette.review)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.strings.notScannedTitle).font(.callout.weight(.semibold))
                Text(model.strings.notScannedBody).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(model.unreadable, id: \.ruleID) { rule in
                    Text("\(rule.ruleID) — \(rule.reason)")
                        .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            Button(model.strings.grantAccess) { model.openFullDiskAccess() }
        }
        .padding(13)
        .background(Palette.review.opacity(0.10), in: .rect(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.review.opacity(0.45)))
    }
}

private struct CleanSummary: View {
    let report: CleanReport
    let strings: Strings

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.safe)
            Text("\(strings.freed) \(formatBytes(report.reclaimedBytes))")
                .font(.callout.weight(.semibold))
            if !report.failures.isEmpty {
                Text(t("\(report.failures.count) skipped", "건너뜀 \(report.failures.count)개"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if report.mode == .trash {
                Text(strings.trashModeNote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .background(Palette.safe.opacity(0.10), in: .rect(cornerRadius: 9))
    }
}

private struct Footer: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.strings.selectionSummary(
                    rules: model.selectedGroups.count, items: model.selectedItemCount
                ))
                .font(.callout.weight(.semibold))
                Text(model.permanentDelete ? model.strings.permanentModeNote : model.strings.trashModeNote)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.selectionExceedsSafe {
                Label(model.strings.aboveSafeWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Palette.caution)
            }
            Picker("", selection: $model.permanentDelete) {
                Text(t("Trash", "휴지통")).tag(false)
                Text(t("Delete", "즉시 삭제")).tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()

            Button(model.strings.emptyTrash) { Task { await model.emptyTrash() } }
                .disabled(model.isBusy)

            Button {
                model.confirming = true
            } label: {
                Text("\(model.permanentDelete ? model.strings.deletePermanently : model.strings.moveToTrash)  \(formatBytes(model.selectedBytes))")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.permanentDelete ? Palette.caution : .accentColor)
            .disabled(model.isBusy || model.selectedGroups.isEmpty)
            .opacity(model.isBusy && model.selectedGroups.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }
}
