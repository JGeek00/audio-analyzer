import AppKit
import SwiftUI

@main
struct BPMCalculatorApp: App {
    @State private var workspace = WorkspaceModel()

    var body: some Scene {
        Window("BPM Calculator", id: "main") {
            WorkspaceView(model: workspace)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 1_100, height: 700)
        .windowResizability(.contentMinSize)
        .commandsReplaced {
            CommandMenu("File") {
                Button("Open files…") {
                    workspace.isImporting = true
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

@MainActor
final class MainWindowDelegate: NSObject, NSWindowDelegate {
    private let model: WorkspaceModel

    init(model: WorkspaceModel) {
        self.model = model
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let message = model.closeWarningMessage else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "There is unfinished work"
        alert.informativeText = message
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Close anyway")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(nil)
    }
}

struct MainWindowAccessor: NSViewRepresentable {
    let model: WorkspaceModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    @MainActor
    final class Coordinator {
        private let model: WorkspaceModel
        private weak var attachedWindow: NSWindow?
        private var delegate: MainWindowDelegate?

        init(model: WorkspaceModel) {
            self.model = model
        }

        func attach(to view: NSView) {
            guard let window = view.window else {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.attach(to: view)
                }
                return
            }
            guard attachedWindow !== window else { return }

            let delegate = MainWindowDelegate(model: model)
            window.delegate = delegate
            self.delegate = delegate
            attachedWindow = window
        }
    }
}
