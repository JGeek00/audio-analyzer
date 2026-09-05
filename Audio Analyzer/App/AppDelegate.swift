import AppKit

/// Receives Finder "Open with" URLs missed by `onOpenURL` (e.g. the rest of
/// a multi-file selection). Both paths call `importTracks`, which dedups.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // NSApplication.shared.delegate is SwiftUI's forwarder, not this instance.
    static weak var shared: AppDelegate?

    private weak var workspace: WorkspaceModel?
    private var pendingURLs: [URL] = []

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func setWorkspace(_ workspace: WorkspaceModel) {
        self.workspace = workspace
        guard !pendingURLs.isEmpty else { return }
        workspace.importTracks(from: pendingURLs)
        pendingURLs.removeAll()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let workspace else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        workspace.importTracks(from: urls)
    }
}
