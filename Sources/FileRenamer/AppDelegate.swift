import AppKit
import FileRenamerCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var settingsController: SettingsController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "📎"
        installDropTarget()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        UI.shared.onRefresh = { [weak self] in
            guard let self else { return }
            self.statusItem.button?.title = Store.shared.pending.isEmpty
                ? "📎"
                : "📎 \(Store.shared.pending.count)"
            ActivityWindow.shared.refresh()
            self.statusItem.menu?.update()
        }
        UI.shared.onOpenSettings = { [weak self] in self?.openSettings() }

        Store.shared.restartWatchers()
    }

    /// Menu bar app: closing the last window (e.g. the splash) must never quit us.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        let store = Store.shared
        let s = store.settings

        addDisabled(menu, s.folders.isEmpty ? "AI FileRenamer — no folders yet" : "AI FileRenamer")
        menu.addItem(.separator())

        // Folders
        for f in s.folders {
            let sub = NSMenu()
            let auto = NSMenuItem(title: "Auto-approve", action: #selector(toggleAuto(_:)), keyEquivalent: "")
            auto.target = self
            auto.representedObject = f.path
            auto.state = f.autoApprove ? .on : .off
            sub.addItem(auto)
            sub.addItem(.separator())
            let scan = NSMenuItem(title: "Rename all files in folder…", action: #selector(renameAll(_:)), keyEquivalent: "")
            scan.target = self
            scan.representedObject = f.path
            scan.toolTip = "Name every file in this folder, including files that existed before you added it"
            sub.addItem(scan)
            sub.addItem(.separator())
            let rm = NSMenuItem(title: "Remove folder", action: #selector(removeFolder(_:)), keyEquivalent: "")
            rm.target = self
            rm.representedObject = f.path
            sub.addItem(rm)

            let item = NSMenuItem(title: shortPath(f.path), action: nil, keyEquivalent: "")
            item.submenu = sub
            menu.addItem(item)
        }
        let add = NSMenuItem(title: "Add Folder…", action: #selector(addFolder), keyEquivalent: "a")
        add.target = self
        menu.addItem(add)
        let pick = NSMenuItem(title: "Rename Files…", action: #selector(openRenamePanel), keyEquivalent: "r")
        pick.target = self
        pick.toolTip = "Pick files in a panel, or drag files onto the 📎 icon in the menu bar"
        menu.addItem(pick)
        menu.addItem(.separator())

        // Pending suggestions
        if !store.pending.isEmpty {
            addDisabled(menu, "Pending approval (\(store.pending.count))")
            for sug in store.pending.prefix(15) {
                let it = NSMenuItem(title: "\(sug.oldName)  →  \(sug.proposedName)",
                                    action: nil, keyEquivalent: "")
                let sub = NSMenu()
                let ap = NSMenuItem(title: "✓  Approve", action: #selector(approve(_:)), keyEquivalent: "")
                ap.target = self
                ap.representedObject = sug.id.uuidString
                sub.addItem(ap)
                let dis = NSMenuItem(title: "✕  Discard", action: #selector(discard(_:)), keyEquivalent: "")
                dis.target = self
                dis.representedObject = sug.id.uuidString
                sub.addItem(dis)
                it.submenu = sub
                menu.addItem(it)
            }
            if store.pending.count > 15 {
                addDisabled(menu, "… and \(store.pending.count - 15) more")
            }
            let all = NSMenuItem(title: "Approve All (\(store.pending.count))",
                                 action: #selector(approveAll), keyEquivalent: "")
            all.target = self
            menu.addItem(all)
            let clear = NSMenuItem(title: "Clear All Pending (\(store.pending.count))",
                                   action: #selector(discardAll), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
            menu.addItem(.separator())
        }

        let undo = NSMenuItem(title: "Undo Last Batch", action: #selector(undoBatch), keyEquivalent: "z")
        undo.target = self
        undo.isEnabled = store.hasUndoableBatch
        menu.addItem(undo)

        let pause = NSMenuItem(title: s.paused ? "▶  Resume" : "⏸  Pause",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        // Recent activity
        let recent = Array(store.events.suffix(8)).reversed()
        if !recent.isEmpty {
            menu.addItem(.separator())
            addDisabled(menu, "Activity (newest first)")
            for e in recent {
                let it = NSMenuItem(title: e.line, action: nil, keyEquivalent: "")
                it.isEnabled = false
                menu.addItem(it)
            }
        }

        menu.addItem(.separator())
        let act = NSMenuItem(title: "Activity…", action: #selector(openActivity), keyEquivalent: "")
        act.target = self
        menu.addItem(act)
        let about = NSMenuItem(title: "About AI FileRenamer…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit AI FileRenamer",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func addDisabled(_ menu: NSMenu, _ title: String) {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        menu.addItem(it)
    }

    private func shortPath(_ p: String) -> String {
        p.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: - Actions

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch"
        panel.message = "Choose a folder to watch for new files"
        if panel.runModal() == .OK, let url = panel.url {
            Store.shared.addFolder(url)
        }
    }

    @objc private func removeFolder(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? String else { return }
        Store.shared.removeFolder(path: p)
    }

    @objc private func toggleAuto(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? String else { return }
        Store.shared.toggleAutoApprove(path: p)
    }

    @objc private func renameAll(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? String else { return }
        Store.shared.renameAllFiles(in: p)
    }

    /// “Rename Files…” — pick any files right now, outside watched folders.
    @objc private func openRenamePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Rename"
        panel.message = "Choose one or more files to name"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        startRename(paths: panel.urls.map { $0.path })
    }

    /// Shared entry point for ad-hoc renames (file panel, drag onto the icon,
    /// Finder Services). Each drop/selection is one batch, processed
    /// sequentially, and undoable as a unit.
    private func startRename(paths: [String]) {
        guard !paths.isEmpty else { return }
        UI.shared.notify("Naming \(paths.count) file\(paths.count == 1 ? "" : "s")…")
        Task { @MainActor in
            let r = await Store.shared.renameSelectedFiles(paths)
            let note = Store.shared.pending.isEmpty ? "" : " Check the menu to approve."
            UI.shared.notify("Done: \(r.done) named, \(r.skipped) skipped.\(note)")
        }
    }

    /// Drag & drop: a transparent view over the menu bar icon accepts file
    /// drags; clicks pass straight through to the button/menu.
    private func installDropTarget() {
        guard let button = statusItem.button else { return }
        let drop = DropTargetView(frame: button.bounds)
        drop.autoresizingMask = [.width, .height]
        drop.button = button
        drop.onFiles = { [weak self] urls in
            self?.startRename(paths: urls.map { $0.path })
        }
        button.addSubview(drop)
    }

    /// Finder Services entry (“Rename with AI FileRenamer”). macOS sends an
    /// array of file paths as strings (or URLs) as the argument.
    @objc func openFiles(_ sender: Any?) {
        var paths: [String] = []
        if let arr = sender as? [Any] {
            for o in arr {
                if let s = o as? String { paths.append(s) }
                else if let u = o as? URL { paths.append(u.path) }
            }
        }
        startRename(paths: paths)
    }

    @objc private func openActivity() {
        ActivityWindow.shared.show()
    }

    @objc private func approve(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let uuid = UUID(uuidString: id) else { return }
        Store.shared.approve(uuid)
    }

    @objc private func approveAll() {
        Store.shared.approveAll()
    }

    @objc private func discard(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let uuid = UUID(uuidString: id) else { return }
        Store.shared.discard(uuid)
    }

    @objc private func discardAll() {
        Store.shared.discardAllPending()
    }

    @objc private func undoBatch() {
        Store.shared.undoLastBatch()
    }

    @objc private func togglePause() {
        Store.shared.setPaused(!Store.shared.settings.paused)
    }

    // MARK: - Settings

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let c = settingsController {
            c.show()
            return
        }
        let c = SettingsController()
        c.onClose = { [weak self] in self?.settingsController = nil }
        settingsController = c
        c.show()
    }
}
