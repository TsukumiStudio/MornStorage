import XCTest
@testable import MornStorage

final class TreemapTests: XCTestCase {
    func testLayoutTilesBoundsWithoutOverlap() {
        let bounds = CGRect(x: 10, y: 20, width: 600, height: 400)
        let weights: [Double] = [6, 6, 4, 3, 2, 2, 1, 0]
        let rects = Treemap.layout(weights, in: bounds)
        XCTAssertEqual(rects.count, weights.count)
        XCTAssertEqual(rects.last, .zero)
        let area = rects.reduce(0) { $0 + $1.width * $1.height }
        XCTAssertEqual(area, bounds.width * bounds.height, accuracy: 0.01)
        for (weight, rect) in zip(weights, rects) where weight > 0 {
            XCTAssertTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(rect), "\(rect)")
            XCTAssertEqual(rect.width * rect.height / (bounds.width * bounds.height), weight / 24, accuracy: 0.0001)
            XCTAssertLessThan(max(rect.width / rect.height, rect.height / rect.width), 3)
        }
        for i in rects.indices where rects[i] != .zero {
            for j in rects.indices where j > i && rects[j] != .zero {
                XCTAssertFalse(rects[i].insetBy(dx: 0.001, dy: 0.001).intersects(rects[j]), "\(i) overlaps \(j)")
            }
        }
        XCTAssertTrue(Treemap.layout([], in: bounds).isEmpty)
        XCTAssertEqual(Treemap.layout([0, 0], in: bounds), [.zero, .zero])
    }

    func testPlaceSkipsTinyRectsAndNestsDirectories() throws {
        let root = Node(url: URL(fileURLWithPath: "/tmp/root"), isDirectory: true, parent: nil)
        let dir = Node(url: root.url.appendingPathComponent("dir"), isDirectory: true, parent: root)
        let big = Node(url: dir.url.appendingPathComponent("big"), isDirectory: false, parent: dir)
        big.size = 1000
        let tiny = Node(url: dir.url.appendingPathComponent("tiny"), isDirectory: false, parent: dir)
        tiny.size = 1
        dir.children = [tiny, big]; dir.size = 1001
        root.children = [dir]; root.size = 1001
        var placed: [Placed] = []
        TreemapView.place(root, in: CGRect(x: 0, y: 0, width: 200, height: 200), depth: 0, maxDepth: 8, into: &placed)
        XCTAssertEqual(placed.map(\.node.name), ["dir", "big"])
        var shallow: [Placed] = []
        TreemapView.place(root, in: CGRect(x: 0, y: 0, width: 200, height: 200), depth: 0, maxDepth: 1, into: &shallow)
        XCTAssertEqual(shallow.map(\.node.name), ["dir"])
        let dirRect = try XCTUnwrap(placed.first?.rect)
        XCTAssertTrue(dirRect.contains(placed[1].rect))
        XCTAssertEqual(big.ancestors.map(\.name), ["root", "dir", "big"])
    }
}
