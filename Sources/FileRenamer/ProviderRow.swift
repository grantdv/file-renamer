import AppKit

/// One editable row for a provider in the Settings window.
final class ProviderRow: NSView {
    private let nameField = NSTextField()
    private let urlField = NSTextField()
    private let modelField = NSTextField()
    private let keyField = NSSecureTextField()
    private let visionCheck = NSButton(checkboxWithTitle: "vision", target: nil, action: nil)
    private let removeBtn = NSButton(title: "✕", target: nil, action: nil)
    var onRemove: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let w: CGFloat = frameRect.width
        nameField.frame = NSRect(x: 0, y: 4, width: 120, height: 22)
        urlField.frame = NSRect(x: 128, y: 4, width: 250, height: 22)
        modelField.frame = NSRect(x: 386, y: 4, width: 130, height: 22)
        keyField.frame = NSRect(x: 524, y: 4, width: 150, height: 22)
        visionCheck.frame = NSRect(x: 0, y: -18, width: 70, height: 20)
        removeBtn.frame = NSRect(x: w - 30, y: 4, width: 26, height: 22)
        removeBtn.target = self
        removeBtn.action = #selector(removeSelf)
        visionCheck.state = .off
        addSubview(nameField)
        addSubview(urlField)
        addSubview(modelField)
        addSubview(keyField)
        addSubview(visionCheck)
        addSubview(removeBtn)
    }

    required init?(coder: NSCoder) { fatalError() }

    func load(_ p: Provider) {
        nameField.stringValue = p.name
        urlField.stringValue = p.baseURL
        modelField.stringValue = p.model
        keyField.stringValue = p.apiKey
        visionCheck.state = p.supportsVision ? .on : .off
    }

    var provider: Provider {
        Provider(
            id: currentID,
            name: nameField.stringValue.isEmpty ? "Provider" : nameField.stringValue,
            baseURL: urlField.stringValue,
            apiKey: keyField.stringValue,
            model: modelField.stringValue,
            supportsVision: visionCheck.state == .on
        )
    }

    var currentID = UUID()
    func setID(_ id: UUID) { currentID = id }

    @objc private func removeSelf() {
        onRemove?()
    }

    /// Height including the vision checkbox row.
    static let rowHeight: CGFloat = 44
}
