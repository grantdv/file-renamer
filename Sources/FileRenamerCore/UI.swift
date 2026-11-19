import AppKit

/// Bridge between background work and the UI.
public final class UI {
    public static let shared = UI()
    public var onRefresh: (() -> Void)?
    public var onOpenSettings: (() -> Void)?

    public func refresh() { onRefresh?() }

    public func notify(_ msg: String) {
        let n = NSUserNotification()
        n.title = "AI FileRenamer"
        n.informativeText = msg
        NSUserNotificationCenter.default.deliver(n)
    }
}
