import SwiftUI

@main
struct BPMCalculatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var workspace = WorkspaceModel()

    var body: some Scene {
        MainWindowScene(model: workspace)

        Settings {
            PreferencesView()
        }
    }
}
