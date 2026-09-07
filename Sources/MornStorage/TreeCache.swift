import Foundation

/// Last completed scan per volume, so the next launch shows a tree immediately while rescanning.
/// Binary layout per node, depth first: name length u16, name utf8, isDirectory u8, size i64, child count u32.
enum TreeCache {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MornStorage", isDirectory: true)
    }

    static func file(for path: String) -> URL {
        let key = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "root"
        return directory.appendingPathComponent(key + ".tree")
    }

    static func save(_ root: Node) throws {
        var data = Data()
        data.reserveCapacity(64 * 1024 * 1024)
        write(root, into: &data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(for: root.path), options: .atomic)
    }

    static func load(path: String) -> (root: Node, date: Date)? {
        let url = file(for: path)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
        var offset = 0
        let root = data.withUnsafeBytes { buffer in read(buffer, &offset, path: path, parent: nil) }
        return root.map { ($0, date) }
    }

    private static func write(_ node: Node, into data: inout Data) {
        let name = Array(node.name.utf8)
        var length = UInt16(min(name.count, Int(UInt16.max)))
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(contentsOf: name.prefix(Int(length)))
        data.append(node.isDirectory ? 1 : 0)
        var size = node.size
        withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }
        var count = UInt32(node.children.count)
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        for child in node.children { write(child, into: &data) }
    }

    private static func read(_ buffer: UnsafeRawBufferPointer, _ offset: inout Int, path: String, parent: Node?) -> Node? {
        guard offset + 2 <= buffer.count else { return nil }
        let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self)); offset += 2
        guard offset + length + 1 + 8 + 4 <= buffer.count else { return nil }
        let name = String(decoding: UnsafeRawBufferPointer(rebasing: buffer[offset..<offset + length]), as: UTF8.self); offset += length
        let isDirectory = buffer[offset] == 1; offset += 1
        let size = buffer.loadUnaligned(fromByteOffset: offset, as: Int64.self); offset += 8
        let count = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)); offset += 4
        let node = Node(path: parent.map { ($0.path.hasSuffix("/") ? $0.path : $0.path + "/") + name } ?? path, isDirectory: isDirectory, parent: parent)
        node.size = size
        node.children.reserveCapacity(count)
        for _ in 0..<count {
            guard let child = read(buffer, &offset, path: path, parent: node) else { return nil }
            node.children.append(child)
        }
        return node
    }
}
