import SwiftUI
import BiumCore

struct DoctorView: View {
    @Bindable var model: AppModel
    @State private var entries: [HomeEntry] = []
    @State private var measuring = false

    struct HomeEntry: Identifiable, Sendable {
        let name: String
        let bytes: Int64
        var id: String { name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DiskCard(disk: model.disk, strings: model.strings)

                if case .accessDenied = Cleaner.trashState() {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.fill").foregroundStyle(Palette.review)
                        Text(Cleaner.fullDiskAccessHint)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(12)
                    .background(Palette.review.opacity(0.10), in: .rect(cornerRadius: 9))
                }

                HStack {
                    Text(model.strings.largestPlaces).font(.headline)
                    Spacer()
                    if measuring { ProgressView().controlSize(.small) }
                }

                ForEach(entries) { entry in
                    HStack {
                        Text(entry.name).font(.callout.monospaced())
                        Spacer()
                        Text(formatBytes(entry.bytes))
                            .font(.callout.weight(.medium)).monospacedDigit()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.background.secondary, in: .rect(cornerRadius: 7))
                }

                Text(model.strings.outsideHomeNote)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .navigationTitle(model.strings.doctor)
        .task { await measure() }
    }

    /// Measuring the home directory is the slow part, so it happens once per
    /// visit and off the main actor.
    private func measure() async {
        guard entries.isEmpty, !measuring else { return }
        measuring = true
        let found = await Task.detached(priority: .utility) { () -> [HomeEntry] in
            let home = Guardrails.home
            let fm = FileManager.default
            guard let names = try? fm.contentsOfDirectory(atPath: home) else { return [] }
            let sizer = SizeCalculator()
            var out: [HomeEntry] = []
            for name in names where name != "Library" || true {
                var isDir: ObjCBool = false
                let path = "\(home)/\(name)"
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                let size = sizer.size(of: path)
                if size.bytes > 100 * 1024 * 1024 {
                    out.append(HomeEntry(name: "~/\(name)", bytes: size.bytes))
                }
            }
            return out.sorted { $0.bytes > $1.bytes }
        }.value
        entries = found
        measuring = false
    }
}

struct DiskCard: View {
    let disk: DiskInfo
    let strings: Strings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(disk.volume, systemImage: "internaldrive").font(.headline)
                Spacer()
            }
            HStack(spacing: 22) {
                stat(strings.total, formatBytes(disk.totalBytes), .secondary)
                stat(strings.available, formatBytes(disk.freeBytes), Palette.safe)
                stat(strings.reclaimable, formatBytes(disk.importantAvailableBytes), .accentColor)
            }
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(tint).monospacedDigit()
        }
    }
}
