import Foundation

enum ReaderMode: String {
    case read, highlight, draw
}

enum PenTool: String, CaseIterable {
    case pen, marker, eraser
}

enum PenWidth: String, CaseIterable {
    case thin, medium, thick

    var pen: CGFloat {
        switch self { case .thin: return 2; case .medium: return 4; case .thick: return 8 }
    }
    var marker: CGFloat {
        switch self { case .thin: return 12; case .medium: return 20; case .thick: return 32 }
    }
    var next: PenWidth {
        switch self { case .thin: return .medium; case .medium: return .thick; case .thick: return .thin }
    }
}

struct ReaderConfig: Equatable {
    var mode: ReaderMode = .read
    var highlightColor: Swatch = .yellow
    var penTool: PenTool = .pen
    var penColor: Swatch = .red
    var penWidth: PenWidth = .medium
    /// Mocha night page tint (true) or the original paper (false).
    var night = true
    /// Whether the annotation layer is drawn while reading.
    var showLayer = true
}
