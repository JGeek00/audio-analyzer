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
        // Quit only when no main window remains; an "Open with" extra may be
        // closing. The closing window is still listed, so exclude it.
        let closing = notification.object as? NSWindow
        DispatchQueue.main.async {
            let mains = NSApplication.shared.windows.filter {
                $0 !== closing && $0.delegate is MainWindowDelegate
            }
            if mains.isEmpty {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
