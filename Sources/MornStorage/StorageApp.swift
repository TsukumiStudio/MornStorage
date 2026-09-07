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
    /// Used bytes of the scanned volume; nil when the target is not a volume root.
    @Published private(set) var expectedBytes: Int64?
    @Published var hovered: Node?
    @Published var extraDepth: [ObjectIdentifier: Int] = [:]
    /// Bumped while scanning so the treemap re-lays out the growing tree.
    @Published private(set) var revision = 0
    let lock = NSLock()
    private var scanner: Scanner?
    private var task: Task<Void, Never>?

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    struct Volume: Identifiable {
        let url: URL
        let name: String
        let total: Int64
        let available: Int64
        var id: String { url.path }
    }

    static func volumes() -> [Volume] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return Volume(url: url, name: values.volumeName ?? url.lastPathComponent,
                          total: Int64(values.volumeTotalCapacity ?? 0), available: Int64(values.volumeAvailableCapacity ?? 0))
        }
    }

    func scan(_ url: URL) {
        cancel()
        let scanner = Scanner(url: url, lock: lock)
        self.scanner = scanner
        isScanning = true
        root = scanner.root
        current = scanner.root
        hovered = nil
        extraDepth = [:]
        progress = ScanProgress()
        let values = try? url.resourceValues(forKeys: [.isVolumeKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        expectedBytes = values?.isVolume == true ? Int64((values?.volumeTotalCapacity ?? 0) - (values?.volumeAvailableCapacity ?? 0)) : nil
        task = Task {
            let poll = Task { [weak self] in
                while !Task.isCancelled {
                    self?.progress = scanner.snapshot()
                    self?.revision += 1
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            await Task.detached(priority: .userInitiated) { scanner.run() }.value
            poll.cancel()
            progress = scanner.snapshot()
            revision += 1
            if self.scanner === scanner { isScanning = false }
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
    @AppStorage("maxDepth") private var maxDepth = 8

    var body: some View {
        VStack(spacing: Spacing.gap) {
            HStack(spacing: Spacing.gap) {
                Menu("ボリュームを選択") {
                    ForEach(StorageModel.volumes()) { volume in
                        Button("\(volume.name)  (\(StorageModel.format(volume.total - volume.available)) / \(StorageModel.format(volume.total)))") {
                            model.scan(volume.url)
                        }
                    }
                }
                .fixedSize().disabled(model.isScanning)
                if let root = model.root {
                    Button("再スキャン") { model.scan(root.url) }
                }
                if model.isScanning {
                    Button("中止") { model.cancel() }.tint(.red)
                }
                Divider().frame(height: Spacing.section)
                breadcrumb
                Spacer()
                depthControls
            }
            .frame(height: Spacing.section * 2)
            Group {
                if let current = model.current {
                    TreemapView(root: current, lock: model.lock, revision: model.revision, maxDepth: maxDepth, extraDepth: model.extraDepth, hovered: $model.hovered) {
                        model.extraDepth[ObjectIdentifier($0), default: 0] += 1
                    }
                } else {
                    Text("ボリュームを選択してスキャンを開始します")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(alignment: .center) {
                if model.isScanning, model.root?.size == 0 { Text("スキャン中…").foregroundStyle(.secondary) }
            }
            .background(Color(white: 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: Spacing.gap) {
                Text(statusText).font(.callout).lineLimit(1).truncationMode(.middle)
                if model.isScanning, let fraction = scanFraction {
                    ProgressView(value: fraction).frame(width: Spacing.section * 8)
                }
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

    private var depthControls: some View {
        HStack(spacing: Spacing.gap / 2) {
            Button { maxDepth -= 1 } label: { Image(systemName: "minus.square") }
                .disabled(maxDepth <= 1).help("表示する階層を浅くする").accessibilityLabel("表示する階層を浅くする")
            Text("\(maxDepth)").monospacedDigit().frame(width: Spacing.section)
            Button { maxDepth += 1 } label: { Image(systemName: "plus.square") }
                .disabled(maxDepth >= 30).help("表示する階層を深くする").accessibilityLabel("表示する階層を深くする")
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: Spacing.gap / 2) {
            ForEach(Array((model.current?.ancestors ?? []).enumerated()), id: \.offset) { index, node in
                if index > 0 { Text("›").foregroundStyle(.secondary) }
                Button(node.name.isEmpty ? "Root" : node.name) { model.current = node }
                    .buttonStyle(.plain)
                    .fontWeight(node === model.current ? .bold : .regular)
            }
        }
    }

    /// Used space is the denominator; metadata and unreadable items keep it under 100% until the walk ends.
    private var scanFraction: Double? {
        guard let expected = model.expectedBytes, expected > 0 else { return nil }
        return min(Double(model.progress.bytes) / Double(expected), 0.99)
    }

    private var statusText: String {
        if model.isScanning {
            let percent = scanFraction.map { "\(Int($0 * 100))%  " } ?? ""
            return "スキャン中 \(percent)\(model.progress.files) ファイル / \(StorageModel.format(model.progress.bytes))" + errorSuffix
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
