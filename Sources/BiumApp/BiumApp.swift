import SwiftUI
import BiumCore
import Foundation

@main
struct BiumApp: App {
    @State private var model = AppModel()

    init() {
        // The window's language comes from L10n; the menu bar's comes from
        // AppKit, which reads AppleLanguages. Align them here so an explicit
        // BIUM_LANG does not leave English menus over a Korean window. The
        // argument domain is volatile, so this affects only this run and is not
        // written to the user's preferences.
        var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        domain["AppleLanguages"] = [L10n.language.rawValue]
        UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

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
