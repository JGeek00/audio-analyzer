import AppKit

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
