import XCTest
@testable import MornStorage

final class StorageModelTests: XCTestCase {
    @MainActor
    func testScanRejectsReentryAndWaitsForCancellationBeforeRestart() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("MornStorageState-\(UUID())")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data(count: 4096).write(to: base.appendingPathComponent("file"))
        let cached = Node(url: base, isDirectory: true, parent: nil)
        cached.size = 123
        try TreeCache.save(cached)
        let cacheFile = TreeCache.file(for: base.path)
        let originalCache = try Data(contentsOf: cacheFile)
        defer {
            try? FileManager.default.removeItem(at: base)
            try? FileManager.default.removeItem(at: cacheFile)
        }
        let model = StorageModel(accessCheck: { true })
        model.cancel()
        XCTAssertEqual(model.scanState, .idle)
        let date = Date(timeIntervalSince1970: 1)
        model.scan(base, showing: cached, date: date)
        XCTAssertEqual(model.scanState, .scanning)
        model.scan(base)
        XCTAssertTrue(model.root === cached, "A repeated scan must not replace the active tree")
        let lastVolume = UserDefaults.standard.string(forKey: "lastVolume")
        model.open(base.appendingPathComponent("other"))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lastVolume"), lastVolume)
        XCTAssertTrue(model.root === cached)
        model.cancel()
        model.cancel()
        XCTAssertEqual(model.scanState, .stopping)
        XCTAssertTrue(model.isScanning, "Keep destructive actions disabled until workers exit")
        model.scan(base)
        XCTAssertTrue(model.root === cached)
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.scanState, .stopped)
        XCTAssertFalse(model.isScanning)
        XCTAssertTrue(model.root === cached)
        XCTAssertEqual(model.cachedDate, date)
        XCTAssertEqual(try Data(contentsOf: cacheFile), originalCache, "Cancelled results must not overwrite the cache")

        model.scan(base)
        XCTAssertEqual(model.scanState, .scanning)
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.scanState, .finished)
        XCTAssertEqual(model.progress.files, 1)
        XCTAssertEqual(model.root?.children.map(\.name), ["file"])
        XCTAssertNil(model.cachedDate)
        // Wait for the completed scan's asynchronous cache write before cleaning up.
        for _ in 0..<200 where TreeCache.load(path: base.path)?.root.children.count != 1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(TreeCache.load(path: base.path)?.root.children.count, 1)
        model.cancel()
        XCTAssertEqual(model.scanState, .finished)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(model.progress.files, 1, "An old poll must not overwrite the finished scan")
    }

    @MainActor
    func testPermissionIsRequiredBeforeOpeningAndRevocationStopsScanning() async throws {
        var granted = false
        let model = StorageModel(accessCheck: { granted })
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("Missing-\(UUID())")
        let lastVolume = UserDefaults.standard.string(forKey: "lastVolume")
        XCTAssertFalse(model.hasFullDiskAccess)
        model.open(path)
        model.scan(path)
        XCTAssertNil(model.root)
        XCTAssertEqual(model.scanState, .idle)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lastVolume"), lastVolume)
        granted = true
        XCTAssertTrue(model.refreshAccess())
        model.scan(path)
        XCTAssertNotNil(model.root)
        XCTAssertEqual(model.scanState, .scanning)
        granted = false
        XCTAssertFalse(model.refreshAccess())
        XCTAssertEqual(model.scanState, .stopping)
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.scanState, .stopped)
        model.scan(path)
        XCTAssertEqual(model.scanState, .stopped)
        XCTAssertNil(TreeCache.load(path: path.path))
    }
}
