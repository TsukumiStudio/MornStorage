import XCTest
@testable import MornStorage

/// Not a pass/fail gate: prints throughput so scanner changes can be compared. Run with MORNSTORAGE_BENCH=<path>.
final class ScannerBench: XCTestCase {
    func testThroughput() throws {
        guard let path = ProcessInfo.processInfo.environment["MORNSTORAGE_BENCH"] else { throw XCTSkip("MORNSTORAGE_BENCH not set") }
        let scanner = Scanner(url: URL(fileURLWithPath: path), lock: NSLock())
        let start = Date()
        scanner.run()
        let seconds = Date().timeIntervalSince(start)
        let progress = scanner.snapshot()
        print("BENCH files=\(progress.files) bytes=\(progress.bytes) errors=\(progress.errors) seconds=\(seconds) files/s=\(Double(progress.files) / seconds)")
    }
}
