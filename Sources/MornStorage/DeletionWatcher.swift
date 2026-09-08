import CoreServices
import Foundation

/// Watches a completed result; additions and size changes wait for the next manual scan.
final class DeletionWatcher {
    private final class Callback {
        let action: ([String], Bool) -> Void
        init(_ action: @escaping ([String], Bool) -> Void) { self.action = action }
    }
    private let stream: FSEventStreamRef

    init?(url: URL, onChange: @escaping ([String], Bool) -> Void) {
        let original = url.path
        guard let resolved = realpath(original, nil) else { return nil }
        let watched = String(cString: resolved)
        free(resolved)
        let callback = Callback { paths, dropped in
            onChange(paths.map { path in
                if path == watched { return original }
                let prefix = watched.hasSuffix("/") ? watched : watched + "/"
                guard path.hasPrefix(prefix) else { return path }
                return (original.hasSuffix("/") ? original : original + "/") + path.dropFirst(prefix.count)
            }, dropped)
        }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(callback).toOpaque(), retain: {
            UnsafeRawPointer(Unmanaged<Callback>.fromOpaque($0!).retain().toOpaque())
        }, release: {
            Unmanaged<Callback>.fromOpaque($0!).release()
        }, copyDescription: nil)
        guard let stream = FSEventStreamCreate(nil, { _, info, count, rawPaths, flags, _ in
            let callback = Unmanaged<Callback>.fromOpaque(info!).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue() as! [String]
            var removed: [String] = []
            var dropped = false
            for index in 0..<count {
                if flags[index] & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0 { dropped = true }
                guard flags[index] & UInt32(kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed) != 0 else { continue }
                var status = stat()
                // Do not mistake permission errors or dangling symlinks for deletion.
                if lstat(paths[index], &status) != 0 && errno == ENOENT { removed.append(paths[index]) }
            }
            if !removed.isEmpty || dropped { callback.action(removed, dropped) }
        }, &context, [watched] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)) else { return nil }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "studio.tsukumi.MornStorage.deletions", qos: .utility))
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
