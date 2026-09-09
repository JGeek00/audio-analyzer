import Combine
import Foundation
import Sparkle

/// Owns Sparkle's updater for the whole app lifetime.
/// ponytail: singleton with default UI, no delegates. Add a delegate when custom update behavior is needed.
@MainActor
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    let objectWillChange = ObservableObjectPublisher()

    let updaterController: SPUStandardUpdaterController

    @Published private(set) var canCheckForUpdates = false

    private var observation: NSKeyValueObservation?

    private init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        observation = updaterController.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    var updater: SPUUpdater {
        updaterController.updater
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyDownloadsUpdates = newValue
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
