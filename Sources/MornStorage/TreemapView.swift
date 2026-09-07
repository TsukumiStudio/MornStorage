import SwiftUI

struct Placed {
    let node: Node
    let rect: CGRect
    let depth: Int
    /// Levels this node inherits for its children before its own adjustment.
    let inherited: Int
    /// Directory whose children are laid out.
    let open: Bool
}

/// Per-folder view state changed by clicks and the depth buttons.
struct DepthState: Equatable {
    var maxDepth = 8
    var closed: Set<ObjectIdentifier> = []
    var extra: [ObjectIdentifier: Int] = [:]

    func childBudget(of node: Node, inherited: Int) -> Int {
        let id = ObjectIdentifier(node)
        return closed.contains(id) ? 0 : max(inherited + (extra[id] ?? 0), 0)
    }

    mutating func toggle(_ placed: Placed) {
        let id = ObjectIdentifier(placed.node)
        if placed.open { closed.insert(id); return }
        closed.remove(id)
        if childBudget(of: placed.node, inherited: placed.inherited) <= 0 { extra[id] = 1 - placed.inherited }
    }

    /// Focused folder: shift its subtree. No focus: shift every visible folder that was not closed by hand.
    mutating func shift(_ delta: Int, focused: Placed?) {
        guard let focused else { maxDepth = max(maxDepth + delta, 1); return }
        let id = ObjectIdentifier(focused.node)
        closed.remove(id)
        extra[id, default: 0] += delta
    }
}

struct TreemapView: View {
    let root: Node
    let lock: NSLock
    let revision: Int
    let state: DepthState
    let focused: Node?
    @Binding var hovered: Node?
    /// nil means the click landed on empty space.
    var onClick: (Placed?) -> Void
    @State private var placed: [Placed] = []

    static let padding: CGFloat = 3
    static let header: CGFloat = 16
    static let minSide: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, _ in
                for item in placed { draw(item, in: &context) }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hovered = placed.last { $0.rect.contains(point) }?.node ?? root
                case .ended: hovered = nil
                }
            }
            .onTapGesture {
                let target = hovered.map { $0.isDirectory ? $0 : $0.parent } ?? nil
                onClick(placed.first { $0.node === target })
            }
            .contextMenu {
                if let hovered {
                    Button("Finderで表示") { NSWorkspace.shared.activateFileViewerSelecting([hovered.url]) }
                }
            }
            .onChange(of: geometry.size, initial: true) { relayout(geometry.size) }
            .onChange(of: ObjectIdentifier(root)) { relayout(geometry.size) }
            .onChange(of: revision) { relayout(geometry.size) }
            .onChange(of: state) { relayout(geometry.size) }
        }
    }

    private func relayout(_ size: CGSize) {
        var result: [Placed] = []
        // ponytail: whole layout under the scanner's lock; the layout is pixel-bounded, so the scan pauses only for milliseconds.
        lock.withLock { Self.place(root, in: CGRect(origin: .zero, size: size), depth: 0, budget: state.childBudget(of: root, inherited: state.maxDepth), state: state, into: &result) }
        placed = result
    }

    /// `budget` is how many more levels may be laid out below `node`.
    static func place(_ node: Node, in rect: CGRect, depth: Int, budget: Int, state: DepthState, into result: inout [Placed]) {
        guard budget > 0 else { return }
        var inner = rect.insetBy(dx: padding, dy: padding)
        if depth > 0, inner.height > header * 2 { inner.origin.y += header; inner.size.height -= header }
        guard inner.width >= minSide, inner.height >= minSide else { return }
        let children = node.children.sorted { $0.size > $1.size }
        let rects = Treemap.layout(children.map { Double($0.size) }, in: inner)
        for (child, childRect) in zip(children, rects) where childRect.width >= minSide && childRect.height >= minSide {
            let childBudget = state.childBudget(of: child, inherited: budget - 1)
            result.append(Placed(node: child, rect: childRect, depth: depth + 1, inherited: budget - 1, open: child.isDirectory && childBudget > 0))
            if child.isDirectory {
                place(child, in: childRect, depth: depth + 1, budget: childBudget, state: state, into: &result)
            }
        }
    }

    static let palette: [Color] = [
        Color(hue: 0.55, saturation: 0.65, brightness: 0.95), Color(hue: 0.80, saturation: 0.55, brightness: 0.95),
        Color(hue: 0.35, saturation: 0.60, brightness: 0.85), Color(hue: 0.10, saturation: 0.70, brightness: 0.98),
        Color(hue: 0.95, saturation: 0.55, brightness: 0.95), Color(hue: 0.48, saturation: 0.60, brightness: 0.85),
        Color(hue: 0.65, saturation: 0.50, brightness: 0.98), Color(hue: 0.16, saturation: 0.65, brightness: 0.95),
    ]

    /// Same extension, same color; hashValue is randomized per process, so fold the bytes by hand.
    static func fileColor(_ name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        let fold = ext.utf8.reduce(7) { ($0 &* 31 &+ Int($1)) & 0x7fffffff }
        return palette[fold % palette.count]
    }

    private func draw(_ item: Placed, in context: inout GraphicsContext) {
        let rect = item.rect.insetBy(dx: 1, dy: 1)
        let path = Path(roundedRect: rect, cornerRadius: 3)
        let isHovered = hovered === item.node
        if item.node.isDirectory {
            let isFocused = focused === item.node
            context.fill(path, with: .color(.white.opacity(isHovered ? 0.10 : 0.03)))
            context.stroke(path, with: .color(isFocused ? Color.accentColor : .white.opacity(isHovered ? 0.9 : 0.25)), lineWidth: isFocused ? 2 : 1)
        } else {
            context.fill(path, with: .color(Self.fileColor(item.node.name).opacity(isHovered ? 1 : 0.85)))
            if isHovered { context.stroke(path, with: .color(.white), lineWidth: 1.5) }
        }
        // Directories get a label only when place() reserved header space, so child labels never overlap it.
        let labelFits = item.node.isDirectory ? item.rect.height - Self.padding * 2 > Self.header * 2 : rect.height >= Self.header
        guard labelFits, rect.width >= Self.header * 2 else { return }
        let label = Text(item.node.name).font(.system(size: 10, weight: item.node.isDirectory ? .semibold : .regular))
            .foregroundStyle(item.node.isDirectory ? Color.white.opacity(0.85) : Color.black.opacity(0.75))
        let text = context.resolve(label)
        let measured = text.measure(in: CGSize(width: rect.width - Self.padding * 2, height: Self.header))
        guard measured.width > 0 else { return }
        context.drawLayer { layer in
            layer.clip(to: Path(rect.insetBy(dx: Self.padding, dy: 0)))
            layer.draw(text, at: CGPoint(x: rect.minX + Self.padding, y: rect.minY + 2), anchor: .topLeading)
        }
    }
}
