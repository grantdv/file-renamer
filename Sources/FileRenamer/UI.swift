import AppKit

/// Bridge between background work and the UI.
final class UI {
    static let shared = UI()
    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    func refresh() { onRefresh?() }

    func notify(_ msg: String) {
        let n = NSUserNotification()
        n.title = "FileRenamer"
        n.informativeText = msg
        NSUserNotificationCenter.default.deliver(n)
    }
}
