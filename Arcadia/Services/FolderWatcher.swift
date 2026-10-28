import CoreServices
import Foundation

/// Watches a folder and everything inside it through FSEvents, and calls `onChange` once
/// files stop appearing, disappearing or being renamed for a moment.
@MainActor
final class FolderWatcher {
    private(set) var folder: URL?
    private nonisolated(unsafe) var stream: FSEventStreamRef?
    private var pending: Task<Void, Never>?
    private let delay: Duration
    private let onChange: @MainActor () -> Void

    init(delay: Duration = .seconds(1), onChange: @escaping @MainActor () -> Void) {
        self.delay = delay
        self.onChange = onChange
    }

    deinit {
        if let stream { Self.close(stream) }
    }

    /// Starts watching `folder`, replacing the previous one; nil stops watching.
    func watch(_ folder: URL?) {
        stop()
        guard let folder else { return }
        self.folder = folder

        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let events = zip(paths, UnsafeBufferPointer(start: flags, count: count)).map { ($0, $1) }
            // The stream delivers on the main queue.
            MainActor.assumeIsolated { watcher.received(events) }
        }
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagWatchRoot
        guard let stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                               FSEventStreamCreateFlags(flags)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        pending?.cancel()
        pending = nil
        folder = nil
        if let stream { Self.close(stream) }
        stream = nil
    }

    private nonisolated static func close(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func received(_ events: [(String, FSEventStreamEventFlags)]) {
        guard let folder, events.contains(where: { Self.matters(path: $0.0, flags: $0.1, in: folder) }) else { return }
        // Copying a batch of games produces a burst of events; scan once it settles.
        pending?.cancel()
        pending = Task { [delay, weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }

    /// Files that appear, disappear or are renamed count; content and metadata changes, and
    /// hidden files such as `.DS_Store`, do not.
    nonisolated static func matters(path: String, flags: FSEventStreamEventFlags, in folder: URL) -> Bool {
        let flags = Int(flags)
        if flags & (kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMustScanSubDirs) != 0 { return true }
        guard flags & (kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved
                       | kFSEventStreamEventFlagItemRenamed) != 0 else { return false }
        let root = URL(fileURLWithPath: realPath(folder)).pathComponents
        var components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        if components.starts(with: root) { components.removeFirst(root.count) }
        return !components.contains { $0.hasPrefix(".") }
    }

    /// The path as FSEvents reports it, such as /private/var/… for /var/….
    nonisolated static func realPath(_ url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path, let resolved = realpath(path, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        } ?? url.standardizedFileURL.path
    }
}
