import AppKit
import FileRenamerCore

/// Settings window: provider list + routing pickers.
final class SettingsController: NSObject {
    var onClose: (() -> Void)?
    private var window: NSWindow!
    private let rowContainer = FlippedView()
    private var rows: [ProviderRow] = []
    private let imagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let textPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let datePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let casePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let wordsPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let rulesField = NSTextField()

    private static let dateOptions = DatePrefixMode.allCases
    private static let caseOptions = CaseStyle.allCases
    private static let wordOptions = WordCountStyle.allCases

    func show() {
        if window == nil { build() }
        reload()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 710, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        w.title = "AI FileRenamer Settings"
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
            l.frame = NSRect(x: x, y: 518, width: 250, height: 16)
            v.addSubview(l)
        }

        rowContainer.frame = NSRect(x: 20, y: 250, width: 680, height: 260)
        v.addSubview(rowContainer)

        let add = NSButton(title: "+ Add Provider", target: self, action: #selector(addRow))
        add.bezelStyle = .rounded
        add.frame = NSRect(x: 20, y: 208, width: 130, height: 30)
        v.addSubview(add)

        let importBtn = NSButton(title: "Import my local setup…", target: self, action: #selector(importLocal))
        importBtn.bezelStyle = .rounded
        importBtn.toolTip = "Pre-fill providers from keys/endpoints already present on this machine"
        importBtn.frame = NSRect(x: 158, y: 208, width: 180, height: 30)
        v.addSubview(importBtn)

        // Routing
        let imgLabel = NSTextField(labelWithString: "Images are named by:")
        imgLabel.frame = NSRect(x: 20, y: 162, width: 150, height: 24)
        v.addSubview(imgLabel)
        imagePopup.frame = NSRect(x: 176, y: 158, width: 220, height: 26)
        v.addSubview(imagePopup)

        let txtLabel = NSTextField(labelWithString: "Text files are named by:")
        txtLabel.frame = NSRect(x: 20, y: 124, width: 160, height: 24)
        v.addSubview(txtLabel)
        textPopup.frame = NSRect(x: 176, y: 120, width: 220, height: 26)
        v.addSubview(textPopup)

        imagePopup.addItem(withTitle: "(none — skip / date fallback)")
        textPopup.addItem(withTitle: "(none — skip / date fallback)")

        // Naming style
        let styleTitle = NSTextField(labelWithString: "Naming style")
        styleTitle.font = NSFont.boldSystemFont(ofSize: 11)
        styleTitle.textColor = .secondaryLabelColor
        styleTitle.frame = NSRect(x: 20, y: 94, width: 200, height: 16)
        v.addSubview(styleTitle)

        let dateLabel = NSTextField(labelWithString: "Date prefix:")
        dateLabel.frame = NSRect(x: 20, y: 66, width: 90, height: 24)
        v.addSubview(dateLabel)
        for m in Self.dateOptions { datePopup.addItem(withTitle: m.display) }
        datePopup.frame = NSRect(x: 112, y: 62, width: 140, height: 26)
        v.addSubview(datePopup)

        let caseLabel = NSTextField(labelWithString: "Case:")
        caseLabel.frame = NSRect(x: 266, y: 66, width: 40, height: 24)
        v.addSubview(caseLabel)
        for m in Self.caseOptions { casePopup.addItem(withTitle: m.display) }
        casePopup.frame = NSRect(x: 306, y: 62, width: 140, height: 26)
        v.addSubview(casePopup)

        let wordsLabel = NSTextField(labelWithString: "Words:")
        wordsLabel.frame = NSRect(x: 460, y: 66, width: 48, height: 24)
        v.addSubview(wordsLabel)
        for m in Self.wordOptions { wordsPopup.addItem(withTitle: m.display) }
        wordsPopup.frame = NSRect(x: 508, y: 62, width: 170, height: 26)
        v.addSubview(wordsPopup)

        let rulesLabel = NSTextField(labelWithString: "Custom rules:")
        rulesLabel.frame = NSRect(x: 20, y: 28, width: 90, height: 24)
        v.addSubview(rulesLabel)
        rulesField.frame = NSRect(x: 112, y: 24, width: 566, height: 24)
        rulesField.placeholderString = "optional, e.g. start with the location of the photo"
        v.addSubview(rulesField)

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

        let style = Store.shared.settings.naming
        datePopup.selectItem(at: Self.dateOptions.firstIndex(of: style.datePrefix) ?? 1)
        casePopup.selectItem(at: Self.caseOptions.firstIndex(of: style.caseStyle) ?? 0)
        wordsPopup.selectItem(at: Self.wordOptions.firstIndex(of: style.wordCount) ?? 1)
        rulesField.stringValue = style.customRules
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
        // capture any unsaved edits in the other rows first so deleting one row doesn't wipe them
        s.providers = rows.map { $0.provider }
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
        var style = s.naming
        if datePopup.indexOfSelectedItem >= 0 { style.datePrefix = Self.dateOptions[datePopup.indexOfSelectedItem] }
        if casePopup.indexOfSelectedItem >= 0 { style.caseStyle = Self.caseOptions[casePopup.indexOfSelectedItem] }
        if wordsPopup.indexOfSelectedItem >= 0 { style.wordCount = Self.wordOptions[wordsPopup.indexOfSelectedItem] }
        style.customRules = rulesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        s.naming = style
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
