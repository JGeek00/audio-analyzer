import SwiftUI

@main
struct BPMCalculatorApp: App {
    @State private var workspace = WorkspaceModel()

    var body: some Scene {
        WindowGroup {
            WorkspaceView(model: workspace)
        }
        .defaultSize(width: 1_100, height: 700)
    }
}
