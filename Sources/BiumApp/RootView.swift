import SwiftUI
import BiumCore

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.screen) {
                Section(model.strings.tools) {
                    label(.scan, model.strings.scan, "magnifyingglass")
                    label(.doctor, model.strings.doctor, "stethoscope")
                    label(.rules, model.strings.rules, "list.bullet.rectangle")
                    label(.history, model.strings.history, "clock.arrow.circlepath")
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) { DiskGauge(disk: model.disk, strings: model.strings) }
        } detail: {
            Group {
                switch model.screen {
                case .scan: ScanView(model: model)
                case .doctor: DoctorView(model: model)
                case .rules: RulesView(model: model)
                case .history: HistoryView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if model.isBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(model.progress ?? model.strings.scanning)
                            .font(.callout).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: 420)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $model.deepScan) { Label(model.strings.deepScan, systemImage: "scope") }
                    .toggleStyle(.button)
                    .help(t("Also walk project trees for stale node_modules and build output. Slower.",
                            "프로젝트 트리를 탐색해서 오래된 node_modules 와 빌드 산출물도 찾습니다. 느립니다."))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.scan() } } label: {
                    Label(model.strings.rescan, systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)
            }
        }
        .alert(t("Could not finish", "완료하지 못했습니다"), isPresented: .constant(model.error != nil)) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private func label(_ screen: Screen, _ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).tag(screen)
    }
}

struct DiskGauge: View {
    let disk: DiskInfo
    let strings: Strings

    private var usedFraction: Double {
        guard disk.totalBytes > 0 else { return 0 }
        return Double(disk.totalBytes - disk.freeBytes) / Double(disk.totalBytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(disk.volume).font(.caption).fontWeight(.medium)
                Spacer()
                Text("\(Int(usedFraction * 100))% \(strings.used)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: usedFraction)
                .tint(usedFraction > 0.9 ? Palette.caution : .accentColor)
            Text("\(formatBytes(disk.freeBytes)) \(strings.available)")
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(12)
    }
}
