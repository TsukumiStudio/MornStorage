import SwiftUI

enum Spacing {
    static let edge: CGFloat = 16
    static let panel: CGFloat = 12
    static let gap: CGFloat = 8
    static let section: CGFloat = 16
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct StorageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = StorageModel()
    @StateObject private var updater = Updater()

    var body: some Scene {
        WindowGroup("MornStorage") {
            ContentView(model: model, updater: updater)
        }
        .defaultSize(width: 1100, height: 720)
    }
}

@MainActor
final class StorageModel: ObservableObject {
    @Published private(set) var root: Node?
    @Published var current: Node?
    @Published private(set) var progress = ScanProgress()
    @Published private(set) var isScanning = false
    @Published var hovered: Node?
    private var scanner: Scanner?
    private var task: Task<Void, Never>?

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "スキャン"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scan(url)
    }

    func scan(_ url: URL) {
        cancel()
        let scanner = Scanner()
        self.scanner = scanner
        isScanning = true
        root = nil
        current = nil
        hovered = nil
        progress = ScanProgress()
        task = Task {
            let poll = Task { [weak self] in
                while !Task.isCancelled {
                    self?.progress = scanner.snapshot()
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            let node = await Task.detached(priority: .userInitiated) { scanner.scan(url) }.value
            poll.cancel()
            progress = scanner.snapshot()
            if self.scanner === scanner {
                root = node
                current = node
                isScanning = false
            }
        }
    }

    func cancel() {
        scanner?.cancel()
        task?.cancel()
        scanner = nil
        isScanning = false
    }
}

struct ContentView: View {
    @ObservedObject var model: StorageModel
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(spacing: Spacing.gap) {
            HStack(spacing: Spacing.gap) {
                Button("フォルダを選択") { model.chooseFolder() }.disabled(model.isScanning)
                if let root = model.root {
                    Button("再スキャン") { model.scan(root.url) }
                }
                if model.isScanning {
                    Button("中止") { model.cancel() }.tint(.red)
                }
                Divider().frame(height: Spacing.section)
                breadcrumb
                Spacer()
            }
            .frame(height: Spacing.section * 2)
            Group {
                if let current = model.current {
                    TreemapView(root: current, hovered: $model.hovered) { model.current = $0 }
                } else {
                    Text(model.isScanning ? "スキャン中…" : "フォルダを選択してスキャンを開始します")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            HStack(spacing: Spacing.gap) {
                Text(statusText).font(.callout).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(freeSpaceText).font(.caption).foregroundStyle(.secondary)
                updateControls
                Text("ver \(Updater.version)").font(.caption).foregroundStyle(.secondary)
            }
            .frame(height: Spacing.section * 2)
        }
        .padding(Spacing.edge)
        .frame(minWidth: 640, minHeight: 400)
        .task {
            // A path argument would make AppKit treat launch as "open file" and skip the window, so use an env var.
            if let path = ProcessInfo.processInfo.environment["MORNSTORAGE_PATH"] {
                model.scan(URL(fileURLWithPath: path))
            }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: Spacing.gap / 2) {
            ForEach(Array((model.current?.ancestors ?? []).enumerated()), id: \.offset) { index, node in
                if index > 0 { Text("›").foregroundStyle(.secondary) }
                Button(node.name.isEmpty ? node.url.path : node.name) { model.current = node }
                    .buttonStyle(.plain)
                    .fontWeight(node === model.current ? .bold : .regular)
            }
        }
    }

    private var statusText: String {
        if model.isScanning {
            return "スキャン中: \(model.progress.files) ファイル / \(StorageModel.format(model.progress.bytes))" + errorSuffix
        }
        guard let node = model.hovered ?? model.current else { return "" }
        return "\(node.url.path)  —  \(StorageModel.format(node.size))" + errorSuffix
    }

    private var errorSuffix: String {
        model.progress.errors > 0 ? "  (読めない項目: \(model.progress.errors))" : ""
    }

    private var freeSpaceText: String {
        guard let url = model.root?.url,
              let free = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity else { return "" }
        return "空き \(StorageModel.format(Int64(free)))"
    }

    @ViewBuilder private var updateControls: some View {
        switch updater.state {
        case .idle:
            Button("更新を確認") { Task { await updater.check() } }
        case .checking:
            Text("更新を確認中…").font(.caption)
        case .available(let tag):
            Button("最新へ更新") { Task { await updater.update() } }.help(tag)
        case .upToDate:
            Button("最新版です ↻") { Task { await updater.check() } }.help("更新を確認")
        case .updating:
            Text("更新中…").font(.caption)
        case .updated:
            Button("再起動して適用") { updater.restart() }
        case .failed(let message):
            Button("確認失敗・再試行") { Task { await updater.check() } }
                .foregroundStyle(.red).help(message).accessibilityHint(message)
        }
    }
}
