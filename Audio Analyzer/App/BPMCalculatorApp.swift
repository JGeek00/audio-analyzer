import SwiftUI

@main
struct BPMCalculatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var workspace = WorkspaceModel()

    init() {
        // Starts Sparkle's updater (automatic background checks).
        _ = UpdaterController.shared
    }

    var body: some Scene {
        MainWindowScene(model: workspace)

        Settings {
            PreferencesView()
        }
    }
}
