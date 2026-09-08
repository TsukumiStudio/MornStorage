import SwiftUI
import Darwin
import OSLog

enum FullDiskAccess {
    static func isGranted() -> Bool {
        // ponytail: macOS has no public FDA query API. Probe protected files without reading
        // their contents; revisit these paths when macOS changes its privacy protection.
        let paths = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path,
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        return paths.contains { path in
            let fd = Darwin.open(path, O_RDONLY | O_CLOEXEC)
            guard fd >= 0 else {
                let code = errno
                Logger(subsystem: "studio.tsukumi.MornStorage", category: "FullDiskAccess")
                    .error("Permission probe failed: errno=\(code)")
                return false
            }
            Darwin.close(fd)
            Logger(subsystem: "studio.tsukumi.MornStorage", category: "FullDiskAccess")
                .info("Permission probe succeeded")
            return true
        }
    }
}

struct FullDiskAccessView: View {
    @ObservedObject var model: StorageModel
    @State private var checked = false
    @State private var restarting = false
    @State private var restartError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            Label("フルディスクアクセスを許可してください", systemImage: "lock.shield")
                .font(.title2.bold())
            Text("MornStorageを使うには、システム設定でフルディスクアクセスを許可する必要があります。")
            Text("「プライバシーとセキュリティ」→「フルディスクアクセス」でMornStorageをオンにしてください。一覧にない場合は、＋からこのアプリを追加します。")
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.gap) {
                Button("システム設定を開く") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                .buttonStyle(.borderedProminent)
                Button("アプリをFinderで表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
            }
            if checked {
                Text("許可済みでも、反映には再起動が必要な場合があります。「再起動して確認」を押してください。")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.gap) {
                Button(model.isCheckingAccess ? "確認中…" : "許可を確認") {
                    Task { checked = !(await model.refreshAccess()) }
                }
                .disabled(model.isCheckingAccess)
                Button(restarting ? "再起動中…" : "再起動して確認") {
                    restarting = true
                    Task {
                        do { try await AppDelegate.restart(at: Bundle.main.bundleURL) }
                        catch {
                            restartError = "再起動できませんでした。MornStorageを終了し、Finderから開き直してください。"
                            restarting = false
                        }
                    }
                }
                .disabled(restarting)
                Button("終了") { NSApp.terminate(nil) }
            }
            if let restartError {
                Text(restartError).foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.edge * 2)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 640, minHeight: 400)
    }
}
