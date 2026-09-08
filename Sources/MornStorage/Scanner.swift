import Foundation

final class Node {
    let name: String
    /// Plain path: building a Foundation URL per entry costs more than the directory read itself.
    let path: String
    let isDirectory: Bool
    var size: Int64 = 0
    var children: [Node] = []
    weak var parent: Node?

    init(path: String, isDirectory: Bool, parent: Node?) {
        self.path = path
        // "/" would be a one-character breadcrumb that is hard to hit.
        self.name = path == "/" ? "Root" : String(path[path.index(after: path.lastIndex(of: "/") ?? path.startIndex)...])
        self.isDirectory = isDirectory
        self.parent = parent
    }

    convenience init(url: URL, isDirectory: Bool, parent: Node?) {
        self.init(path: url.path, isDirectory: isDirectory, parent: parent)
    }

    var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }

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

/// Grows `root` in place. Directories are walked in parallel with getattrlistbulk (one syscall per
/// buffer of entries instead of one stat per file). Every tree mutation happens under `lock`,
/// so readers that hold `lock` can lay out the partial tree while the scan continues.
final class Scanner: @unchecked Sendable {
    let root: Node
    let lock: NSLock
    private var progress = ScanProgress()
    private var cancelled = false
    private let queue = DispatchQueue(label: "studio.tsukumi.MornStorage.scan", qos: .userInitiated, attributes: .concurrent)
    private let group = DispatchGroup()

    init(url: URL, lock: NSLock) {
        root = Node(url: url, isDirectory: true, parent: nil)
        self.lock = lock
    }

    func snapshot() -> ScanProgress { lock.withLock { progress } }
    func cancel() { lock.withLock { cancelled = true } }
    private var isCancelled: Bool { lock.withLock { cancelled } }

    func run() {
        walk(root)
        group.wait()
    }

    private func walk(_ directory: Node) {
        if isCancelled { return }
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { lock.withLock { progress.errors += 1 }; return }
        defer { close(fd) }
        var files: [Node] = [], directories: [Node] = []
        var bytes: Int64 = 0
        var request = attrlist(bitmapcount: u_short(ATTR_BIT_MAP_COUNT), reserved: 0,
                               commonattr: attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_OBJTYPE),
                               volattr: 0, dirattr: attrgroup_t(ATTR_DIR_MOUNTSTATUS), fileattr: attrgroup_t(ATTR_FILE_ALLOCSIZE), forkattr: 0)
        let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 256 * 1024, alignment: 8)
        defer { buffer.deallocate() }
        while true {
            if isCancelled { return }
            let count = getattrlistbulk(fd, &request, buffer, 256 * 1024, 0)
            if count < 0 { lock.withLock { progress.errors += 1 }; break }
            if count == 0 { break }
            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                var field = entry + 4
                let returned = field.loadUnaligned(as: attribute_set_t.self)
                field += MemoryLayout<attribute_set_t>.size
                var name = ""
                if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
                    let reference = field.loadUnaligned(as: attrreference_t.self)
                    name = String(cString: (field + Int(reference.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                    field += MemoryLayout<attrreference_t>.size
                }
                var type: fsobj_type_t = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                    type = field.loadUnaligned(as: fsobj_type_t.self)
                    field += MemoryLayout<fsobj_type_t>.size
                }
                var mountStatus: UInt32 = 0
                if returned.dirattr & attrgroup_t(ATTR_DIR_MOUNTSTATUS) != 0 {
                    mountStatus = field.loadUnaligned(as: UInt32.self)
                    field += MemoryLayout<UInt32>.size
                }
                var allocated: Int64 = 0
                if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                    allocated = field.loadUnaligned(as: off_t.self)
                }
                entry += length
                if type == UInt32(VDIR.rawValue) {
                    // Another volume's mount point (e.g. /Volumes/X, /System/Volumes/Data) belongs to that volume's scan.
                    if mountStatus & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0 { continue }
                    directories.append(Node(path: prefix + name, isDirectory: true, parent: directory))
                } else {
                    // Symlinks and everything else count as files, so a link never doubles or loops its target.
                    let child = Node(path: prefix + name, isDirectory: false, parent: directory)
                    child.size = allocated
                    files.append(child)
                    bytes += allocated
                }
            }
        }
        lock.withLock {
            guard !cancelled else { return }
            directory.children.append(contentsOf: files)
            directory.children.append(contentsOf: directories)
            var node: Node? = directory
            while let current = node { current.size += bytes; node = current.parent }
            progress.files += files.count
            progress.bytes += bytes
        }
        for child in directories {
            if isCancelled { return }
            group.enter()
            queue.async { self.walk(child); self.group.leave() }
        }
    }
}
