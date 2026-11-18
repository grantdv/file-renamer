import AppKit

/// Settings window: provider list + routing pickers.
final class SettingsController: NSObject {
    var onClose: (() -> Void)?
    private var window: NSWindow!
    private let rowContainer = FlippedView()
    private var rows: [ProviderRow] = []
    private let imagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let textPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    func show() {
        if window == nil { build() }
        reload()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 710, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        w.title = "FileRenamer Settings"
        w.isReleasedWhenClosed = false
        w.delegate = self
        window = w
        let v = w.contentView!

        // Column headers
        let headers: [(String, CGFloat)] = [
            ("Name", 0), ("Base URL (OpenAI-compatible)", 128), ("Model", 386), ("API Key", 524)
        ]
        for (t, x) in headers {
            let l = NSTextField(labelWithString: t)
            l.font = NSFont.boldSystemFont(ofSize: 11)
            l.textColor = .secondaryLabelColor
            l.frame = NSRect(x: x, y: 428, width: 250, height: 16)
            v.addSubview(l)
        }

        rowContainer.frame = NSRect(x: 20, y: 160, width: 680, height: 260)
        v.addSubview(rowContainer)

        let add = NSButton(title: "+ Add Provider", target: self, action: #selector(addRow))
        add.bezelStyle = .rounded
        add.frame = NSRect(x: 20, y: 118, width: 130, height: 30)
        v.addSubview(add)

        let importBtn = NSButton(title: "Import my local setup…", target: self, action: #selector(importLocal))
        importBtn.bezelStyle = .rounded
        importBtn.toolTip = "Pre-fill providers from keys/endpoints already present on this machine"
        importBtn.frame = NSRect(x: 158, y: 118, width: 180, height: 30)
        v.addSubview(importBtn)

        // Routing
        let imgLabel = NSTextField(labelWithString: "Images are named by:")
        imgLabel.frame = NSRect(x: 20, y: 72, width: 150, height: 24)
        v.addSubview(imgLabel)
        imagePopup.frame = NSRect(x: 176, y: 68, width: 220, height: 26)
        v.addSubview(imagePopup)

        let txtLabel = NSTextField(labelWithString: "Text files are named by:")
        txtLabel.frame = NSRect(x: 20, y: 34, width: 160, height: 24)
        v.addSubview(txtLabel)
        textPopup.frame = NSRect(x: 176, y: 30, width: 220, height: 26)
        v.addSubview(textPopup)

        imagePopup.addItem(withTitle: "(none — skip / date fallback)")
        textPopup.addItem(withTitle: "(none — skip / date fallback)")

        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 600, y: 16, width: 90, height: 30)
        v.addSubview(save)
    }

    private func reload() {
        rowContainer.subviews.forEach { $0.removeFromSuperview() }
        rows = Store.shared.settings.providers.map { p in
            let row = ProviderRow(frame: .zero)
            row.setID(p.id)
            row.load(p)
            row.onRemove = { [weak self] in
                guard let self else { return }
                self.removeRow(row)
            }
            rows.append(row)
            return row
        }
        layoutRows()

        imagePopup.removeAllItems()
        textPopup.removeAllItems()
        imagePopup.addItem(withTitle: "(none — skip / date fallback)")
        textPopup.addItem(withTitle: "(none — skip / date fallback)")
        for p in Store.shared.settings.providers {
            let title = p.supportsVision ? "\(p.name)  (vision)" : p.name
            imagePopup.addItem(withTitle: title)
            textPopup.addItem(withTitle: title)
        }
        if let id = Store.shared.settings.imageProviderID,
           let i = Store.shared.settings.providers.firstIndex(where: { $0.id == id }) {
            imagePopup.selectItem(at: i + 1)
        } else {
            imagePopup.selectItem(at: 0)
        }
        if let id = Store.shared.settings.textProviderID,
           let i = Store.shared.settings.providers.firstIndex(where: { $0.id == id }) {
            textPopup.selectItem(at: i + 1)
        } else {
            textPopup.selectItem(at: 0)
        }
    }

    private func layoutRows() {
        for (i, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(i) * ProviderRow.rowHeight, width: rowContainer.bounds.width, height: ProviderRow.rowHeight)
            rowContainer.addSubview(row)
        }
    }

    // MARK: - Actions

    @objc private func addRow() {
        let p = Provider(name: "New Provider",
                         baseURL: "https://api.openai.com/v1",
                         apiKey: "",
                         model: "",
                         supportsVision: false)
        var s = Store.shared.settings
        s.providers.append(p)
        Store.shared.saveSettings(with: s)
        reload()
    }

    @objc private func removeRow(_ row: ProviderRow) {
        var s = Store.shared.settings
        s.providers.removeAll { $0.id == row.currentID }
        if s.imageProviderID == row.currentID { s.imageProviderID = nil }
        if s.textProviderID == row.currentID { s.textProviderID = nil }
        Store.shared.saveSettings(with: s)
        reload()
    }

    @objc private func importLocal() {
        let n = Store.shared.autoImportProviders()
        reload()
        let alert = NSAlert()
        alert.messageText = n == 0 ? "Nothing to import" : "Imported \(n) provider\(n == 1 ? "" : "s")"
        alert.informativeText = n == 0
            ? "No OpenAI key or local LLM endpoint was found on this machine. Add one manually above."
            : "Check the details before saving."
        alert.runModal()
    }

    @objc private func save() {
        var s = Store.shared.settings
        s.providers = rows.map { $0.provider }
        let imgIdx = imagePopup.indexOfSelectedItem
        let txtIdx = textPopup.indexOfSelectedItem
        s.imageProviderID = imgIdx > 0 ? s.providers[imgIdx - 1].id : nil
        s.textProviderID = txtIdx > 0 ? s.providers[txtIdx - 1].id : nil
        Store.shared.saveSettings(with: s)
        window.close()
    }
}

extension SettingsController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
