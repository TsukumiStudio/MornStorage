import XCTest
@testable import MornStorage

final class TreeCacheTests: XCTestCase {
    func testRoundTripPreservesTree() throws {
        let root = Node(path: "/", isDirectory: true, parent: nil)
        let dir = Node(path: "/dir", isDirectory: true, parent: root)
        let file = Node(path: "/dir/日本語.txt", isDirectory: false, parent: dir)
        file.size = 1234; dir.size = 1234; root.size = 1234
        dir.children = [file]; root.children = [dir]
        try TreeCache.save(root)
        defer { try? FileManager.default.removeItem(at: TreeCache.file(for: "/")) }
        let loaded = try XCTUnwrap(TreeCache.load(path: "/"))
        XCTAssertEqual(loaded.root.name, "Root")
        XCTAssertEqual(loaded.root.size, 1234)
        let loadedFile = try XCTUnwrap(loaded.root.children.first?.children.first)
        XCTAssertEqual(loadedFile.path, "/dir/日本語.txt")
        XCTAssertEqual(loadedFile.name, "日本語.txt")
        XCTAssertFalse(loadedFile.isDirectory)
        XCTAssertTrue(loadedFile.parent === loaded.root.children.first)
        XCTAssertNil(TreeCache.load(path: "/no-such-cache-\(UUID())"))
    }
}
