import PDFKit

/// Maps between PDF page space (origin bottom-left, unrotated crop box) and
/// "unit" space: (0…1, 0…1) with a top-left origin, as the page is *displayed*.
struct PageGeometry {
    let bounds: CGRect
    let rotation: Int

    init(page: PDFPage) {
        bounds = page.bounds(for: .cropBox)
        rotation = ((page.rotation % 360) + 360) % 360
    }

    var displaySize: CGSize {
        rotation % 180 == 0 ? bounds.size : CGSize(width: bounds.height, height: bounds.width)
    }

    func unit(fromPage p: CGPoint) -> CGPoint {
        let a = (p.x - bounds.minX) / bounds.width
        let b = (p.y - bounds.minY) / bounds.height
        switch rotation {
        case 90: return CGPoint(x: b, y: a)
        case 180: return CGPoint(x: 1 - a, y: b)
        case 270: return CGPoint(x: 1 - b, y: 1 - a)
        default: return CGPoint(x: a, y: 1 - b)
        }
    }

    func page(fromUnit u: CGPoint) -> CGPoint {
        let a: CGFloat, b: CGFloat
        switch rotation {
        case 90: b = u.x; a = u.y
        case 180: a = 1 - u.x; b = u.y
        case 270: b = 1 - u.x; a = 1 - u.y
        default: a = u.x; b = 1 - u.y
        }
        return CGPoint(x: bounds.minX + a * bounds.width, y: bounds.minY + b * bounds.height)
    }

    func unitRect(fromPage r: CGRect) -> CGRect {
        let corners = [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
        ].map(unit(fromPage:))
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
