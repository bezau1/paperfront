import Foundation
import CoreGraphics

/// A highlight lives in the annotation layer, never in the PDF itself.
/// `rects` are in PDF page space (crop-box coordinates, origin bottom-left).
struct Highlight: Identifiable, Codable, Hashable {
    var id = UUID()
    var page: Int
    var rects: [CGRect]
    var text: String
    var color: Swatch
    var note: String = ""
    var createdAt = Date()
}

/// Everything stored in the secret layer for one item.
struct AnnotationFile: Codable {
    var highlights: [Highlight] = []
    /// PKDrawing data keyed by page index, stored in "canonical" page-point space.
    var drawings: [String: Data] = [:]
}
