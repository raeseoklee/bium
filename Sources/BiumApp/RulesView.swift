import SwiftUI
import BiumCore

struct RulesView: View {
    @Bindable var model: AppModel
    @State private var query = ""

    private var filtered: [Rule] {
        let all = Rules.all()
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter {
            $0.id.lowercased().contains(q)
                || $0.title.lowercased().contains(q)
                || $0.detail.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(SafetyLevel.allCases, id: \.self) { level in
                    let rules = filtered.filter { $0.safety == level }
                    if !rules.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Label(level.label, systemImage: level.symbol)
                                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(level.tint, in: .rect(cornerRadius: 5))
                                Text(level.localized).font(.callout.weight(.semibold))
                                Text(model.strings.ruleCount(rules.count))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(rules, id: \.id) { rule in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(rule.title).font(.callout.weight(.medium))
                                        Text(rule.id).font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(.quaternary, in: .rect(cornerRadius: 4))
                                        if rule.deep {
                                            Text("--deep").font(.caption2.monospaced())
                                                .foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                        Text(rule.category.localized)
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    Text(rule.detail).font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.background.secondary, in: .rect(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .searchable(text: $query, prompt: t("Search rules", "규칙 검색"))
        .navigationTitle(model.strings.rules)
    }
}
