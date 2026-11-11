import UIKit

/// Draws highlight rectangles (given in unit space) above the page image.
final class HighlightView: UIView {
    struct Item {
        var rects: [CGRect]
        var color: UIColor
    }

    var items: [Item] = [] { didSet { setNeedsDisplay() } }
    var preview: [CGRect] = [] { didSet { setNeedsDisplay() } }
    var previewColor: UIColor = .yellow

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        func scaled(_ u: CGRect) -> CGRect {
            CGRect(x: u.minX * bounds.width, y: u.minY * bounds.height,
                   width: u.width * bounds.width, height: u.height * bounds.height)
        }
        for item in items {
            item.color.withAlphaComponent(0.42).setFill()
            for r in item.rects { UIBezierPath(roundedRect: scaled(r), cornerRadius: 2).fill() }
        }
        previewColor.withAlphaComponent(0.55).setFill()
        for r in preview { UIBezierPath(roundedRect: scaled(r), cornerRadius: 2).fill() }
    }
}
