import Foundation

enum ItemKind: String, Codable, CaseIterable {
    case book
    case document

    var title: String { self == .book ? "Books" : "Documents" }
    var singular: String { self == .book ? "Book" : "Document" }
}

enum SourceFormat: String, Codable {
    case pdf, epub, text, markdown, rtf, html, image
}

struct LibraryItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var author: String = ""
    var kind: ItemKind
    var format: SourceFormat
    var addedAt = Date()
    var lastOpenedAt: Date?
    var lastPage = 0
    var pageCount = 0
    var sourceURL: String?

    var progress: Double {
        guard pageCount > 1 else { return 0 }
        return min(1, Double(lastPage) / Double(pageCount - 1))
    }
}
