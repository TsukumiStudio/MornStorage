import XCTest
@testable import MornStorage

final class ScannerTests: XCTestCase {
    func testSizesPropagateToAncestorsAndSymlinksAreNotFollowed() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("MornStorageTests-\(UUID().uuidString)")
        let deep = base.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try Data(count: 8192).write(to: deep.appendingPathComponent("f1"))
        try Data(count: 4096).write(to: base.appendingPathComponent("f2"))
        try FileManager.default.createSymbolicLink(at: base.appendingPathComponent("loop"), withDestinationURL: base)
        defer { try? FileManager.default.removeItem(at: base) }

        let scanner = Scanner(url: base, lock: NSLock())
        scanner.run()
        let root = scanner.root
        XCTAssertEqual(scanner.snapshot().files, 3)
        XCTAssertGreaterThanOrEqual(root.size, 12288)
        let a = try XCTUnwrap(root.children.first { $0.name == "a" })
        let b = try XCTUnwrap(a.children.first { $0.name == "b" })
        XCTAssertEqual(a.size, b.size)
        XCTAssertGreaterThanOrEqual(b.size, 8192)
        XCTAssertEqual(root.size, a.size + root.children.filter { !$0.isDirectory }.reduce(0) { $0 + $1.size })
        XCTAssertFalse(try XCTUnwrap(root.children.first { $0.name == "loop" }).isDirectory)
    }
}

extension ScannerTests {
    func testRootVolumeIsNamedRoot() {
        XCTAssertEqual(Node(url: URL(fileURLWithPath: "/"), isDirectory: true, parent: nil).name, "Root")
        XCTAssertEqual(Node(url: URL(fileURLWithPath: "/Users"), isDirectory: true, parent: nil).name, "Users")
    }
}
