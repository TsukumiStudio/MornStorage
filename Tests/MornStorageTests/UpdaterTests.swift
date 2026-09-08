import XCTest
@testable import MornStorage

@MainActor
final class UpdaterTests: XCTestCase {
    func testRestartReportsLaunchFailure() async {
        do {
            try await AppDelegate.restart(at: URL(fileURLWithPath: "/missing-MornStorage-\(UUID()).app"))
            XCTFail("起動に失敗したら、現在のアプリを終了せずエラーを返す")
        } catch { }
    }

    func testVersionAndProcessFailures() async throws {
        XCTAssertTrue(Updater.isNewer(latestTag: "v0.10.0", current: "0.9.9"))
        XCTAssertFalse(Updater.isNewer(latestTag: "v0.3", current: "0.3.0"))
        XCTAssertFalse(Updater.isNewer(latestTag: "v0.2.9", current: "0.3.0"))
        for invalid in ["", "v", "1..2", "1.-2.3", "+1.0", "1.0-beta", "99999999999999999999999", "１.0"] {
            XCTAssertNil(Updater.parseVersion(invalid), invalid)
        }
        try await Updater.run("/usr/bin/true", [])
        do {
            try await Updater.run("/usr/bin/false", [])
            XCTFail("更新コマンドの失敗を成功扱いしてはいけません")
        } catch { }
        do {
            try await Updater.run("/missing-morndesktoptube-command", [])
            XCTFail("起動できないコマンドを成功扱いしてはいけません")
        } catch { }
    }

    func testCommandFailureIncludesStderrAndLargeOutputDoesNotBlock() async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("MornStorage-update-test-\(UUID()).log")
        let script = log.appendingPathExtension("sh")
        try "head -c 131072 /dev/zero; echo 'permission denied test' >&2; exit 7".write(to: script, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: script)
        }
        do {
            try await Updater.run("/bin/sh", [script.path], logURL: log)
            XCTFail("失敗したコマンドを成功扱いしてはいけません")
        } catch {
            XCTAssertEqual((error as NSError).code, 7)
            XCTAssertTrue(error.localizedDescription.contains("permission denied test"))
            XCTAssertLessThan(error.localizedDescription.count, 5000)
        }
        let output = try Data(contentsOf: log)
        XCTAssertGreaterThan(output.count, 131072)
        XCTAssertTrue(String(decoding: output.suffix(100), as: UTF8.self).contains("permission denied test"))
    }
}
