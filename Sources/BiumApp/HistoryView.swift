import SwiftUI
import BiumCore

struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var entries: [Entry] = []

    struct Entry: Identifiable {
        let file: String
        let report: CleanReport
        var id: String { file }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if entries.isEmpty {
                    ContentUnavailableView(
                        model.strings.noHistory,
                        systemImage: "clock",
                        description: Text(Cleaner.logDirectory).font(.caption.monospaced())
                    )
                    .padding(.top, 60)
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.report.finishedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.callout.weight(.semibold))
                            Text(entry.report.mode == .trash
                                 ? t("to Trash", "휴지통으로")
                                 : t("deleted", "즉시 삭제"))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(formatBytes(entry.report.reclaimedBytes))
                                .font(.callout.weight(.bold)).monospacedDigit()
                        }
                        HStack(spacing: 12) {
                            Text(t("\(entry.report.outcomes.count) items",
                                   "항목 \(entry.report.outcomes.count)개"))
                            if !entry.report.failures.isEmpty {
                                Text(t("\(entry.report.failures.count) skipped",
                                       "건너뜀 \(entry.report.failures.count)개"))
                                    .foregroundStyle(Palette.review)
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: .rect(cornerRadius: 8))
                }
            }
            .padding(20)
        }
        .navigationTitle(model.strings.history)
        .task { load() }
    }

    private func load() {
        let dir = Cleaner.logDirectory
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = names.filter { $0.hasSuffix(".json") }.sorted(by: >).compactMap { name in
            guard let data = fm.contents(atPath: "\(dir)/\(name)"),
                  let report = try? decoder.decode(CleanReport.self, from: data)
            else { return nil }
            return Entry(file: name, report: report)
        }
    }
}
