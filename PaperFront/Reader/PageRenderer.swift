import PDFKit
import UIKit

enum PageRenderer {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 160 * 1024 * 1024
        return c
    }()

    static func flush() { cache.removeAllObjects() }

    /// Renders a page at `size` points. In night mode the paper is inverted and
    /// remapped into Catppuccin Mocha (base background, text-coloured ink).
    static func image(for page: PDFPage, key: String, size: CGSize, night: Bool, scale: CGFloat) -> UIImage {
        let cacheKey = "\(key)-\(Int(size.width))x\(Int(size.height))-\(night ? "n" : "p")" as NSString
        if let hit = cache.object(forKey: cacheKey) { return hit }

        let px = CGSize(width: size.width * scale, height: size.height * scale)
        let base = page.thumbnail(of: px, for: .cropBox)
        var result = base
        if night {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            result = UIGraphicsImageRenderer(size: px, format: format).image { ctx in
                let rect = CGRect(origin: .zero, size: px)
                base.draw(in: rect)
                let c = ctx.cgContext
                c.setBlendMode(.difference)
                c.setFillColor(UIColor.white.cgColor)
                c.fill(rect)
                c.setBlendMode(.lighten)
                c.setFillColor(Mocha.baseUI.cgColor)
                c.fill(rect)
                c.setBlendMode(.darken)
                c.setFillColor(Mocha.textUI.cgColor)
                c.fill(rect)
            }
        }
        cache.setObject(result, forKey: cacheKey, cost: Int(px.width * px.height * 4))
        return result
    }
}
