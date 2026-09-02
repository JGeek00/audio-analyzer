import SwiftUI

@main
struct BPMCalculatorApp: App {
    @State private var workspace = WorkspaceModel()

    var body: some Scene {
        WindowGroup {
            WorkspaceView(model: workspace)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 1_100, height: 700)
        .windowResizability(.contentMinSize)
    }
}
