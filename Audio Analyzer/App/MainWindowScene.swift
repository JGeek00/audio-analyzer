import SwiftUI

struct MainWindowScene: Scene {
    let model: WorkspaceModel
    @AppStorage(AppStorageKeys.appTheme) private var theme = AppConfiguration.defaultTheme.rawValue

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: theme) ?? AppConfiguration.defaultTheme
    }

    var body: some Scene {
        Window("Audio Analyzer", id: "main") {
            WorkspaceView(model: model)
                .frame(minWidth: 700, minHeight: 500)
                .preferredColorScheme(selectedTheme.colorScheme)
                .onOpenURL { url in
                    model.importTracks(from: [url])
                }
        }
        .handlesExternalEvents(
            matching: [
                "public.mp3", "org.xiph.flac", "com.apple.m4a-audio",
                "org.xiph.ogg-audio", "com.microsoft.waveform-audio"
            ])
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
