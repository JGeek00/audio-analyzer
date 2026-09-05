import SwiftUI

struct MainWindowScene: Scene {
    let model: WorkspaceModel
    @AppStorage(AppStorageKeys.appTheme) private var theme = AppConfiguration.defaultTheme.rawValue

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: theme) ?? AppConfiguration.defaultTheme
    }

    var body: some Scene {
        // WindowGroup: routing "Open with" to a Window(id:) destroys it while
        // open; the group absorbs the extra instance, which dismisses itself.
        WindowGroup("Audio Analyzer", id: "main") {
            WorkspaceView(model: model)
                .frame(minWidth: 700, minHeight: 500)
                .preferredColorScheme(selectedTheme.colorScheme)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onOpenURL { url in
                    model.importTracks(from: [url])
                }
                .onAppear {
                    AppDelegate.shared?.setWorkspace(model)
                }
        }
        // ponytail: must match * so a cold open shows the window; UTIs never
        // match file:// URLs.
        .handlesExternalEvents(matching: ["*"])
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
