import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var settingsController: SettingsController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "📎"

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        UI.shared.onRefresh = { [weak self] in
            self?.statusItem.menu?.update()
        }
        UI.shared.onOpenSettings = { [weak self] in self?.openSettings() }

        Store.shared.restartWatchers()
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        let store = Store.shared
        let s = store.settings

        addDisabled(menu, s.folders.isEmpty ? "FileRenamer — no folders yet" : "FileRenamer")
        menu.addItem(.separator())

        // Folders
        for f in s.folders {
            let sub = NSMenu()
            let auto = NSMenuItem(title: "Auto-approve", action: #selector(toggleAuto(_:)), keyEquivalent: "")
            auto.target = self
            auto.representedObject = f.path
            auto.state = f.autoApprove ? .on : .off
            sub.addItem(auto)
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
        menu.addItem(.separator())

        // Pending suggestions
        if !store.pending.isEmpty {
            addDisabled(menu, "Pending approval (\(store.pending.count))")
            for sug in store.pending.prefix(15) {
                let it = NSMenuItem(title: "✓  \(sug.oldName)  →  \(sug.proposedName)",
                                    action: #selector(approve(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = sug.id.uuidString
                menu.addItem(it)
            }
            if store.pending.count > 15 {
                addDisabled(menu, "… and \(store.pending.count - 15) more")
            }
            let all = NSMenuItem(title: "Approve All (\(store.pending.count))",
                                 action: #selector(approveAll), keyEquivalent: "")
            all.target = self
            menu.addItem(all)
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

        // Recent renames
        let recent = Array(s_records(store).reversed())
        if !recent.isEmpty {
            menu.addItem(.separator())
            addDisabled(menu, "Recent")
            for r in recent {
                let it = NSMenuItem(
                    title: "↩ \(URL(fileURLWithPath: r.oldPath).lastPathComponent) → \(URL(fileURLWithPath: r.newPath).lastPathComponent)",
                    action: nil, keyEquivalent: "")
                it.isEnabled = false
                menu.addItem(it)
            }
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit FileRenamer",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func s_records(_ store: Store) -> [RenameRecord] {
        Array(store.records.suffix(5))
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

    @objc private func approve(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let uuid = UUID(uuidString: id) else { return }
        Store.shared.approve(uuid)
    }

    @objc private func approveAll() {
        Store.shared.approveAll()
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
