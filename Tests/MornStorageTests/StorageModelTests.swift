import XCTest
import os
@testable import MornStorage

final class StorageModelTests: XCTestCase {
    @MainActor
    func testExternalDeletionUpdatesTreeWithoutRescanning() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("MornStorageLive-\(UUID())")
        let folder = base.appendingPathComponent("folder")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(count: 8192).write(to: folder.appendingPathComponent("removed"))
        try Data(count: 4096).write(to: folder.appendingPathComponent("remaining"))
        try Data(count: 4096).write(to: base.appendingPathComponent("keep"))
        let link = base.appendingPathComponent("link")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "missing")
        defer {
            try? fm.removeItem(at: base)
            try? fm.removeItem(at: TreeCache.file(for: base.path))
        }
        let model = StorageModel(accessCheck: { true })
        await model.refreshAccess()
        model.selectVolume(base, name: "監視テスト")
        model.startScan()
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.scanState, .finished)
        XCTAssertNil(model.liveUpdateWarning)
        let root = try XCTUnwrap(model.root)
        let directory = try XCTUnwrap(root.children.first { $0.name == "folder" })
        let keep = try XCTUnwrap(root.children.first { $0.name == "keep" })
        let symlink = try XCTUnwrap(root.children.first { $0.name == "link" })
        let original = root.size
        XCTAssertGreaterThan(directory.size, 0)
        for _ in 0..<200 where TreeCache.load(path: base.path) == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(TreeCache.load(path: base.path))

        // A rename event for a dangling symlink must not be mistaken for a deletion.
        let temporaryLink = base.appendingPathComponent("renamed-link")
        try fm.moveItem(at: link, to: temporaryLink)
        try fm.moveItem(at: temporaryLink, to: link)
        try fm.removeItem(at: folder.appendingPathComponent("removed"))
        for _ in 0..<160 where directory.children.contains(where: { $0.name == "removed" }) { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(directory.children.map(\.name), ["remaining"], "A real filesystem event must remove only the deleted file")
        XCTAssertLessThan(root.size, original)
        XCTAssertEqual(root.size, keep.size + symlink.size + directory.size)
        XCTAssertTrue(root.children.contains { $0 === symlink })
        XCTAssertTrue(model.root === root, "Do not replace the tree with an automatic rescan")
        XCTAssertEqual(model.scanState, .finished)

        model.current = directory
        try fm.moveItem(at: folder, to: base.appendingPathComponent("moved-folder"))
        for _ in 0..<160 where root.children.contains(where: { $0 === directory }) { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(root.children.contains { $0 === directory })
        XCTAssertEqual(root.size, keep.size + symlink.size)
        XCTAssertTrue(model.current === root, "Return to the surviving parent when the open folder disappears")
        XCTAssertFalse(root.children.contains { $0.name == "moved-folder" }, "Additions wait for an explicit scan")
        for _ in 0..<100 where TreeCache.load(path: base.path) != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(TreeCache.load(path: base.path), "Deleted entries must not return from an old cache")
    }

    @MainActor
    func testSelectingVolumeWaitsForExplicitStart() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("MornStorageSelect-\(UUID())")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: base)
            try? FileManager.default.removeItem(at: TreeCache.file(for: base.path))
        }
        let model = StorageModel(accessCheck: { true })
        await model.refreshAccess()
        model.startScan()
        XCTAssertNil(model.root)
        model.selectVolume(base, name: "テストストレージ")
        await model.refreshAccess()
        XCTAssertEqual(model.selectedVolumeName, "テストストレージ")
        XCTAssertEqual(model.selectedVolume, base)
        XCTAssertEqual(model.scanState, .idle)
        XCTAssertNil(model.root, "Selecting a volume or rechecking access must not start scanning")
        XCTAssertNil(TreeCache.load(path: base.path))
        model.startScan()
        XCTAssertEqual(model.scanState, .scanning)
        model.selectVolume(base.appendingPathComponent("other"), name: "別のストレージ")
        XCTAssertEqual(model.selectedVolume, base, "The target cannot change during a scan")
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.scanState, .finished)
        for _ in 0..<200 where TreeCache.load(path: base.path) == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(TreeCache.load(path: base.path))
        model.selectVolume(base, name: "テストストレージ")
        XCTAssertEqual(model.scanState, .idle)
        XCTAssertNil(model.root, "Reselecting a cached volume must not rescan")
    }

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
        await model.refreshAccess()
        model.cancel()
        XCTAssertEqual(model.scanState, .idle)
        let date = Date(timeIntervalSince1970: 1)
        model.scan(base, showing: cached, date: date)
        XCTAssertEqual(model.scanState, .scanning)
        model.scan(base)
        XCTAssertTrue(model.root === cached, "A repeated scan must not replace the active tree")
        let selectedVolume = model.selectedVolume
        model.selectVolume(base.appendingPathComponent("other"), name: "別のストレージ")
        XCTAssertEqual(model.selectedVolume, selectedVolume)
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
        let granted = OSAllocatedUnfairLock(initialState: false)
        let model = StorageModel(accessCheck: { granted.withLock { $0 } })
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("Missing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: TreeCache.file(for: path.path)) }
        let selectedVolume = model.selectedVolume
        XCTAssertFalse(model.hasFullDiskAccess)
        model.selectVolume(path, name: "未許可のストレージ")
        model.scan(path)
        XCTAssertNil(model.root)
        XCTAssertEqual(model.scanState, .idle)
        XCTAssertEqual(model.selectedVolume, selectedVolume)
        granted.withLock { $0 = true }
        let allowed = await model.refreshAccess()
        XCTAssertTrue(allowed)
        model.scan(path)
        XCTAssertNotNil(model.root)
        XCTAssertEqual(model.scanState, .scanning)
        granted.withLock { $0 = false }
        let revoked = await model.refreshAccess()
        XCTAssertFalse(revoked)
        XCTAssertNotEqual(model.scanState, .scanning, "Revocation must cancel a scan that is still running")
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isScanning)
        let settled = model.scanState
        model.scan(path)
        XCTAssertEqual(model.scanState, settled)
        // A tiny scan can finish while the asynchronous permission check is in flight.
        if settled == .finished {
            for _ in 0..<200 where TreeCache.load(path: path.path) == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertNotNil(TreeCache.load(path: path.path))
        } else {
            XCTAssertNil(TreeCache.load(path: path.path))
        }
    }

    @MainActor
    func testSlowPermissionCheckLeavesMainThreadFreeAndIsShared() async {
        let started = expectation(description: "permission check started")
        let release = DispatchSemaphore(value: 0)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let model = StorageModel(accessCheck: {
            XCTAssertFalse(Thread.isMainThread, "OS permission checks must not block the UI")
            calls.withLock { $0 += 1 }
            started.fulfill()
            _ = release.wait(timeout: .now() + 2)
            return true
        })
        XCTAssertEqual(calls.withLock { $0 }, 0, "Creating the model must not perform disk I/O")
        let first = Task { await model.refreshAccess() }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(model.isCheckingAccess)
        XCTAssertFalse(model.hasFullDiskAccess)
        XCTAssertFalse(model.canScan)
        let duplicateStarted = expectation(description: "duplicate check requested")
        let second = Task {
            duplicateStarted.fulfill()
            return await model.refreshAccess()
        }
        await fulfillment(of: [duplicateStarted], timeout: 1)
        XCTAssertEqual(calls.withLock { $0 }, 1)
        release.signal()
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertTrue(firstResult && secondResult)
        XCTAssertEqual(calls.withLock { $0 }, 1)
        XCTAssertTrue(model.hasFullDiskAccess)
        XCTAssertFalse(model.isCheckingAccess)
        XCTAssertTrue(model.canScan)
    }
}
