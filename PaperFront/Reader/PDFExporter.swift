import PDFKit
import PencilKit
import UIKit

enum ExportError: LocalizedError {
    case failed
    var errorDescription: String? { "The annotated PDF couldn't be created." }
}

/// Turns the secret layer into standard PDF annotations (highlight + ink) on a
/// *copy* of the document, so they show up in Apple Books, Preview, Acrobat…
enum PDFExporter {
    static func write(document: PDFDocument, annotations: AnnotationStore, to url: URL) throws {
        guard let data = document.dataRepresentation(), let copy = PDFDocument(data: data) else { throw ExportError.failed }

        for index in 0..<copy.pageCount {
            guard let page = copy.page(at: index) else { continue }
            let geometry = PageGeometry(page: page)

            for h in annotations.highlights(onPage: index) where !h.rects.isEmpty {
                let union = h.rects.dropFirst().reduce(h.rects[0]) { $0.union($1) }
                let a = PDFAnnotation(bounds: union, forType: .highlight, withProperties: nil)
                a.color = h.color.uiColor.withAlphaComponent(0.5)
                if !h.note.isEmpty { a.contents = h.note }
                a.quadrilateralPoints = h.rects.flatMap { r -> [NSValue] in
                    let o = union.origin
                    return [
                        NSValue(cgPoint: CGPoint(x: r.minX - o.x, y: r.maxY - o.y)),
                        NSValue(cgPoint: CGPoint(x: r.maxX - o.x, y: r.maxY - o.y)),
                        NSValue(cgPoint: CGPoint(x: r.minX - o.x, y: r.minY - o.y)),
                        NSValue(cgPoint: CGPoint(x: r.maxX - o.x, y: r.minY - o.y)),
                    ]
                }
                page.addAnnotation(a)
            }

            if let drawingData = annotations.drawingData(page: index), let drawing = try? PKDrawing(data: drawingData) {
                let canon = geometry.displaySize
                for stroke in drawing.strokes {
                    let points: [CGPoint] = stroke.path.interpolatedPoints(by: .distance(3)).map { p in
                        let l = p.location.applying(stroke.transform)
                        return geometry.page(fromUnit: CGPoint(x: l.x / canon.width, y: l.y / canon.height))
                    }
                    guard let first = points.first else { continue }
                    let width = max(0.6, stroke.path.first?.size.width ?? 3)
                    let xs = points.map(\.x), ys = points.map(\.y)
                    let bounds = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
                        .insetBy(dx: -width, dy: -width)

                    let a = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
                    a.color = stroke.ink.inkType == .marker ? stroke.ink.color.withAlphaComponent(0.4) : stroke.ink.color
                    let border = PDFBorder()
                    border.lineWidth = width
                    a.border = border

                    let path = UIBezierPath()
                    let origin = bounds.origin
                    path.move(to: CGPoint(x: first.x - origin.x, y: first.y - origin.y))
                    if points.count == 1 {
                        path.addLine(to: CGPoint(x: first.x - origin.x + 0.1, y: first.y - origin.y))
                    }
                    for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.x - origin.x, y: p.y - origin.y)) }
                    a.add(path)
                    page.addAnnotation(a)
                }
            }
        }
        guard copy.write(to: url) else { throw ExportError.failed }
    }
}
