import AppKit

/// Transparent overlay that sits on top of the menu bar button and accepts
/// file drags from Finder. `hitTest` returns nil, so clicks and menu opening
/// are unaffected — only drag sessions reach this view.
final class DropTargetView: NSView {
    var onFiles: (([URL]) -> Void)?
    weak var button: NSStatusBarButton?

    private var highlighting = false
    private var savedTitle: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Let mouse events fall through to the status item button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func setHighlighting(_ on: Bool) {
        guard on != highlighting else { return }
        highlighting = on
        if on {
            savedTitle = button?.title
            button?.title = "📥"
        } else if let t = savedTitle {
            button?.title = t
            savedTitle = nil
        }
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        setHighlighting(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setHighlighting(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setHighlighting(false)
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let objs = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts),
              let urls = objs as? [URL], !urls.isEmpty else { return false }
        onFiles?(urls)
        return true
    }

    func operationFlags(for dragInfo: NSDraggingInfo) -> NSDragOperation {
        [.copy]
    }
}
