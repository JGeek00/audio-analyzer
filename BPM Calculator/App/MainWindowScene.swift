import SwiftUI

struct MainWindowScene: Scene {
    let model: WorkspaceModel
    @AppStorage(AppStorageKeys.appTheme) private var theme = AppConfiguration.defaultTheme.rawValue

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: theme) ?? AppConfiguration.defaultTheme
    }

    var body: some Scene {
        Window("BPM Calculator", id: "main") {
            WorkspaceView(model: model)
                .frame(minWidth: 700, minHeight: 500)
                .preferredColorScheme(selectedTheme.colorScheme)
        }
        .defaultSize(width: 1_100, height: 700)
        .windowResizability(.contentMinSize)
        .commandsReplaced {
            CommandGroup(replacing: .newItem) {
                Button("Open files…") {
                    model.isImporting = true
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}
