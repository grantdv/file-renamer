import Cocoa
import FileRenamerCore

/// Full activity log window (read-only monospace list + Clear).
final class ActivityWindow {
    static let shared = ActivityWindow()

    private var window: NSWindow?
    private let textView = NSTextView()

    private init() {}

    func show() {
        let w = ensureWindow()
        refresh()
        w.center()
        if w.isVisible == false { w.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Cheap enough to call on every refresh; no-op until the window exists.
    func refresh() {
        guard textView.window != nil else { return }
        let lines = Store.shared.events.map(\.line)
        textView.string = lines.isEmpty
            ? "(no activity yet)"
            : lines.reversed().joined(separator: "\n")
        textView.scrollToEndOfDocument(nil)
    }

    private func ensureWindow() -> NSWindow {
        if let w = window, w.isVisible { return w }

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 460),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "AI FileRenamer — Activity"
        w.isReleasedWhenClosed = false

        let content = NSView()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.autoresizingMask = [.width, .height]

        textView.isEditable = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView

        let clear = NSButton(title: "Clear", target: self, action: #selector(clearTapped))
        clear.bezelStyle = .rounded
        clear.frame = NSRect(x: 0, y: 0, width: 80, height: 28)
        clear.autoresizingMask = [.minXMargin, .maxYMargin]

        let header = NSTextField(labelWithString: "Newest first — renames, skips, and errors, with timestamps.")
        header.font = NSFont.systemFont(ofSize: 11)
        header.textColor = .secondaryLabelColor
        header.frame = NSRect(x: 8, y: 0, width: 560, height: 18)
        header.autoresizingMask = [.minYMargin]

        let bar = NSView()
        bar.autoresizingMask = [.width, .minYMargin]
        bar.addSubview(clear)
        clear.frame = NSRect(x: w.frame.width - 90, y: 6, width: 80, height: 28)
        bar.addSubview(header)
        header.frame = NSRect(x: 8, y: 10, width: 560, height: 18)
        bar.frame = NSRect(x: 0, y: 0, width: w.frame.width, height: 40)

        scroll.frame = NSRect(x: 0, y: 40, width: w.frame.width, height: w.frame.height - 40)
        content.addSubview(scroll)
        content.addSubview(bar)
        w.contentView = content
        self.window = w
        return w
    }

    @objc private func clearTapped() {
        Store.shared.clearActivity()
        refresh()
    }
}
