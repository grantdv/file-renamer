import AppKit
import FileRenamerCore

/// Finder Services plugin: right-click a file → Services → “Rename with AI FileRenamer”.
///
/// macOS launches this tiny helper and sends it the `NSServiceName` selector
/// (see the Info.plist of FileRenamerService.app) with an array of file
/// paths. It hands them to the same Store/NamingEngine the menu bar app
/// uses, shows the result, and exits.
final class ServiceDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The service action arrives right after launch; nothing to do here.
    }

    @objc func RenameWithAIFileRenamer(_ sender: Any?) {
        var paths: [String] = []
        if let arr = sender as? [Any] {
            for o in arr {
                if let s = o as? String { paths.append(s) }
                else if let u = o as? URL { paths.append(u.path) }
            }
        }
        guard !paths.isEmpty else {
            NSLog("FileRenamerService: no files received, exiting")
            NSApp.terminate(nil)
            return
        }
        NSLog("FileRenamerService: naming \(paths.count) file(s) from Finder")
        Task { @MainActor in
            let r = await Store.shared.renameSelectedFiles(paths)
            let note = Store.shared.pending.isEmpty
                ? ""
                : " Open the AI FileRenamer menu bar icon to approve."
            UI.shared.notify("AI FileRenamer: \(r.done) named, \(r.skipped) skipped.\(note)")
            // Brief pause so the notification renders, then exit — the menu
            // bar app (if running) owns the long-lived state from here.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            NSApp.terminate(nil)
        }
    }
}

let app = NSApplication.shared
let delegate = ServiceDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
