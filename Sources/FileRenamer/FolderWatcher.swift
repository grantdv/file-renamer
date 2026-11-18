import Foundation

/// Watches one folder with FSEvents; fires `onChange` (on the main queue) when anything inside changes.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let folder: URL
    private let onChange: () -> Void

    init(folder: URL, onChange: @escaping () -> Void) {
        self.folder = folder
        self.onChange = onChange
    }

    func start() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        let paths = [folder.path as CFString] as CFArray
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let w = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
                DispatchQueue.main.async { w.onChange() }
            },
            &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags
        ) else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(s)
    }

    func stop() {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
        stream = nil
    }
}
