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
    /// Set while a previous scan's tree is on screen and a fresh scan runs behind it.
    @Published private(set) var cachedDate: Date?
    @Published var hovered: Node?
    @Published var depth = DepthState(maxDepth: UserDefaults.standard.object(forKey: "maxDepth") as? Int ?? 3)
    @Published var focused: Placed?
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

    /// Shows the last completed scan of this volume right away (when one is saved), then rescans behind it.
    func open(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: "lastVolume")
        if let cached = TreeCache.load(path: url.path) {
            scan(url, showing: cached.root, date: cached.date)
        } else {
            scan(url)
        }
    }

    func scan(_ url: URL, showing cached: Node? = nil, date: Date? = nil) {
        cancel()
        let scanner = Scanner(url: url, lock: lock)
        self.scanner = scanner
        isScanning = true
        root = cached ?? scanner.root
        current = root
        cachedDate = date
        hovered = nil
        depth = DepthState(maxDepth: depth.maxDepth)
        focused = nil
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
            guard self.scanner === scanner else { return }
            isScanning = false
            if cached != nil {
                root = scanner.root
                current = scanner.root
                cachedDate = nil
                depth = DepthState(maxDepth: depth.maxDepth)
                focused = nil
            }
            Task.detached(priority: .utility) { try? TreeCache.save(scanner.root) }
        }
    }

    func menu(_ action: TreemapView.MenuAction, _ item: Placed) {
        switch action {
        case .detail:
            focused = item
            depth.shift(1, focused: item)
        case .simple:
            focused = item
            depth.shift(-1, focused: item)
        case .zoom:
            current = item.node
            focused = nil
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([item.node.url])
        case .delete:
            trash(item.node)
        }
    }

    /// Moves to the Trash (recoverable) after confirmation, then drops the node from the tree.
    private func trash(_ node: Node) {
        guard !isScanning, let parent = node.parent else { return }
        let alert = NSAlert()
        alert.messageText = "「\(node.name)」をゴミ箱に入れますか?"
        alert.informativeText = "\(node.path)\n\(Self.format(node.size))"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "ゴミ箱に入れる")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
            return
        }
        lock.withLock {
            parent.children.removeAll { $0 === node }
            var ancestor: Node? = parent
            while let current = ancestor { current.size -= node.size; ancestor = current.parent }
        }
        if current.map({ $0.ancestors.contains { $0 === node } }) == true { current = parent }
        if focused?.node.ancestors.contains(where: { $0 === node }) == true { focused = nil }
        hovered = nil
        revision += 1
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
                Menu("ボリュームを選択") {
                    ForEach(StorageModel.volumes()) { volume in
                        Button("\(volume.name)  (\(StorageModel.format(volume.total - volume.available)) / \(StorageModel.format(volume.total)))") {
                            model.open(volume.url)
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
            .contentShape(Rectangle())
            .onTapGesture { model.focused = nil }
            Group {
                if let current = model.current {
                    TreemapView(root: current, lock: model.lock, revision: model.revision, state: model.depth, focused: model.focused?.node, hovered: $model.hovered, canDelete: !model.isScanning) { placed in
                        model.focused = placed
                        if let placed { model.depth.toggle(placed) }
                    } onMenu: { action, item in
                        model.menu(action, item)
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
            } else if let last = UserDefaults.standard.string(forKey: "lastVolume") {
                model.open(URL(fileURLWithPath: last))
            }
        }
    }

    private var depthControls: some View {
        HStack(spacing: Spacing.gap / 2) {
            Button { shift(-1) } label: { Image(systemName: "minus.square") }
                .disabled(model.focused == nil && model.depth.maxDepth <= 1)
                .help("表示する階層を浅くする").accessibilityLabel("表示する階層を浅くする")
            Button { shift(1) } label: { Image(systemName: "plus.square") }
                .help("表示する階層を深くする").accessibilityLabel("表示する階層を深くする")
        }
    }

    private func shift(_ delta: Int) {
        model.depth.shift(delta, focused: model.focused)
        UserDefaults.standard.set(model.depth.maxDepth, forKey: "maxDepth")
    }

    private var breadcrumb: some View {
        HStack(spacing: Spacing.gap / 2) {
            ForEach(Array((model.current?.ancestors ?? []).enumerated()), id: \.offset) { index, node in
                if index > 0 { Text("›").foregroundStyle(.secondary) }
                Button(node.name) { model.current = node }
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
            let cached = model.cachedDate.map { "前回 (\($0.formatted(date: .numeric, time: .shortened))) の結果を表示中 · " } ?? ""
            return "\(cached)スキャン中 \(percent)\(model.progress.files) ファイル / \(StorageModel.format(model.progress.bytes))" + errorSuffix
        }
        guard let node = model.hovered ?? model.current else { return "" }
        return "\(node.path)  —  \(StorageModel.format(node.size))" + errorSuffix
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
