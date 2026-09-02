import SwiftUI

@main
struct BPMCalculatorApp: App {
    @State private var workspace = WorkspaceModel()

    var body: some Scene {
        MainWindowScene(model: workspace)

        Settings {
            PreferencesView()
        }
    }
}
