import SwiftUI

struct Placed {
    let node: Node
    let rect: CGRect
    let depth: Int
}

struct TreemapView: View {
    let root: Node
    @Binding var hovered: Node?
    var onOpen: (Node) -> Void
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
                guard let target = hovered.map({ $0.isDirectory ? $0 : $0.parent }) ?? nil, target !== root else { return }
                onOpen(target)
            }
            .contextMenu {
                if let hovered {
                    Button("Finderで表示") { NSWorkspace.shared.activateFileViewerSelecting([hovered.url]) }
                }
            }
            .onChange(of: geometry.size, initial: true) { relayout(geometry.size) }
            .onChange(of: ObjectIdentifier(root)) { relayout(geometry.size) }
        }
    }

    private func relayout(_ size: CGSize) {
        var result: [Placed] = []
        Self.place(root, in: CGRect(origin: .zero, size: size), depth: 0, into: &result)
        placed = result
    }

    static func place(_ node: Node, in rect: CGRect, depth: Int, into result: inout [Placed]) {
        var inner = rect.insetBy(dx: padding, dy: padding)
        if depth > 0, inner.height > header * 2 { inner.origin.y += header; inner.size.height -= header }
        guard inner.width >= minSide, inner.height >= minSide else { return }
        let rects = Treemap.layout(node.children.map { Double($0.size) }, in: inner)
        for (child, childRect) in zip(node.children, rects) where childRect.width >= minSide && childRect.height >= minSide {
            result.append(Placed(node: child, rect: childRect, depth: depth + 1))
            if child.isDirectory { place(child, in: childRect, depth: depth + 1, into: &result) }
        }
    }

    private func draw(_ item: Placed, in context: inout GraphicsContext) {
        let rect = item.rect.insetBy(dx: 0.5, dy: 0.5)
        let path = Path(roundedRect: rect, cornerRadius: 2)
        let fill = item.node.isDirectory
            ? Color(hue: 0.08, saturation: 0.45, brightness: max(0.55, 0.95 - Double(item.depth) * 0.06))
            : Color(hue: 0.58, saturation: 0.5, brightness: 0.9)
        context.fill(path, with: .color(fill))
        if hovered === item.node { context.fill(path, with: .color(.black.opacity(0.12))) }
        context.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 1)
        guard rect.height >= Self.header, rect.width >= Self.header * 2 else { return }
        let text = context.resolve(Text(item.node.name).font(.system(size: 10)).foregroundStyle(.black.opacity(0.85)))
        let measured = text.measure(in: CGSize(width: rect.width - Self.padding * 2, height: Self.header))
        guard measured.width > 0 else { return }
        context.drawLayer { layer in
            layer.clip(to: Path(rect.insetBy(dx: Self.padding, dy: 0)))
            layer.draw(text, at: CGPoint(x: rect.minX + Self.padding, y: rect.minY + 2), anchor: .topLeading)
        }
    }
}
