import Foundation

final class Node {
    let name: String
    let url: URL
    let isDirectory: Bool
    var size: Int64 = 0
    var children: [Node] = []
    weak var parent: Node?

    init(url: URL, isDirectory: Bool, parent: Node?) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.parent = parent
    }

    var ancestors: [Node] {
        var chain: [Node] = []
        var node: Node? = self
        while let current = node { chain.insert(current, at: 0); node = current.parent }
        return chain
    }
}

struct ScanProgress {
    var files = 0
    var bytes: Int64 = 0
    var errors = 0
}

/// Walks a directory tree synchronously on the calling thread; `snapshot()` and `cancel()` are thread-safe.
final class Scanner: @unchecked Sendable {
    private let lock = NSLock()
    private var progress = ScanProgress()
    private var cancelled = false
    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    func snapshot() -> ScanProgress { lock.withLock { progress } }
    func cancel() { lock.withLock { cancelled = true } }
    private var isCancelled: Bool { lock.withLock { cancelled } }

    func scan(_ url: URL) -> Node {
        let root = Node(url: url, isDirectory: true, parent: nil)
        walk(root)
        return root
    }

    private func walk(_ directory: Node) {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: Array(Self.keys), options: [])
        } catch {
            lock.withLock { progress.errors += 1 }
            return
        }
        var pending = 0
        for entry in entries {
            if isCancelled { return }
            guard let values = try? entry.resourceValues(forKeys: Self.keys) else {
                lock.withLock { progress.errors += 1 }
                continue
            }
            // Symlinks count as tiny files so a link never doubles or loops its target.
            if values.isDirectory == true, values.isSymbolicLink != true {
                let child = Node(url: entry, isDirectory: true, parent: directory)
                walk(child)
                directory.children.append(child)
                directory.size += child.size
            } else {
                let child = Node(url: entry, isDirectory: false, parent: directory)
                child.size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                directory.children.append(child)
                directory.size += child.size
                pending += 1
            }
        }
        directory.children.sort { $0.size > $1.size }
        lock.withLock { progress.files += pending; progress.bytes += directory.children.filter { !$0.isDirectory }.reduce(0) { $0 + $1.size } }
    }
}
