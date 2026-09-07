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

/// Grows `root` in place on the calling thread. Every tree mutation happens under `lock`,
/// so readers that hold `lock` can lay out the partial tree while the scan continues.
final class Scanner: @unchecked Sendable {
    let root: Node
    let lock: NSLock
    private var progress = ScanProgress()
    private var cancelled = false
    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isVolumeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    init(url: URL, lock: NSLock) {
        root = Node(url: url, isDirectory: true, parent: nil)
        self.lock = lock
    }

    func snapshot() -> ScanProgress { lock.withLock { progress } }
    func cancel() { lock.withLock { cancelled = true } }
    private var isCancelled: Bool { lock.withLock { cancelled } }

    func run() { walk(root) }

    private func walk(_ directory: Node) {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: Array(Self.keys), options: [])
        } catch {
            lock.withLock { progress.errors += 1 }
            return
        }
        var files: [Node] = [], directories: [Node] = []
        var bytes: Int64 = 0, errors = 0
        for entry in entries {
            if isCancelled { return }
            guard let values = try? entry.resourceValues(forKeys: Self.keys) else { errors += 1; continue }
            // Another volume's mount point (e.g. /Volumes/X, /System/Volumes/Data) belongs to that volume's scan.
            if values.isVolume == true { continue }
            // Symlinks count as tiny files so a link never doubles or loops its target.
            if values.isDirectory == true, values.isSymbolicLink != true {
                directories.append(Node(url: entry, isDirectory: true, parent: directory))
            } else {
                let child = Node(url: entry, isDirectory: false, parent: directory)
                child.size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                files.append(child)
                bytes += child.size
            }
        }
        lock.withLock {
            directory.children.append(contentsOf: files)
            directory.children.append(contentsOf: directories)
            var node: Node? = directory
            while let current = node { current.size += bytes; node = current.parent }
            progress.files += files.count
            progress.bytes += bytes
            progress.errors += errors
        }
        for child in directories { walk(child) }
    }
}
