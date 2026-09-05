import AppKit
import SwiftUI

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
            attachedWindow = window

            // Single main window: another valid instance means SwiftUI routed
            // "Open with" here. Hide and close it delegate-free (no alerts,
            // no quit); both share the model.
            let otherMains = NSApplication.shared.windows.filter {
                $0 !== window && $0.delegate is MainWindowDelegate
            }
            if !otherMains.isEmpty {
                window.orderOut(nil)
                DispatchQueue.main.async {
                    window.close()
                }
                return
            }

            let delegate = MainWindowDelegate(model: model)
            window.delegate = delegate
            self.delegate = delegate
        }
    }
}
