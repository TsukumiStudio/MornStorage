import SwiftUI
import Darwin

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
            guard fd >= 0 else { return false }
            Darwin.close(fd)
            return true
        }
    }
}

struct FullDiskAccessView: View {
    @ObservedObject var model: StorageModel
    @State private var checked = false

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
                Text("アクセスを確認できませんでした。許可後も進めない場合は、MornStorageを終了して開き直してください。")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.gap) {
                Button("許可を確認") { checked = !model.refreshAccess() }
                Button("終了") { NSApp.terminate(nil) }
            }
        }
        .padding(Spacing.edge * 2)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 640, minHeight: 400)
    }
}
