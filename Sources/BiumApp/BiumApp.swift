import SwiftUI
import BiumCore

@main
struct BiumApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("bium", id: "main") {
            RootView(model: model)
                .frame(minWidth: 940, minHeight: 620)
                .task { await model.scan() }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1180, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button(model.strings.rescan) { Task { await model.scan() } }
                    .keyboardShortcut("r")
                    .disabled(model.isBusy)
            }
        }
    }
}
