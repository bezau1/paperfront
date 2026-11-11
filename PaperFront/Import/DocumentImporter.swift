import UIKit
import PDFKit
import UniformTypeIdentifiers

struct ImportResult {
    var title: String
    var author: String
    var format: SourceFormat
    var pageCount: Int
    var cover: UIImage?
}

enum ImportError: LocalizedError {
    case unsupported(String)
    case unreadable
    case locked
    case badURL
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .unsupported(let ext):
            return "PaperFront can't open “.\(ext)” files yet. It reads PDF, EPUB, text, Markdown, RTF, HTML and images."
        case .unreadable: return "That file couldn't be read."
        case .locked: return "This PDF is password protected. Remove the password and try again."
        case .badURL: return "That doesn't look like a valid link."
        case .http(let code): return "The server answered with error \(code)."
        }
    }
}

@MainActor
enum DocumentImporter {
    static let contentTypes: [UTType] = {
        var types: [UTType] = [.pdf, .epub, .plainText, .rtf, .html, .image]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        return types
    }()

    static func prettyTitle(_ filename: String) -> String {
        let base = (filename as NSString).deletingPathExtension
        return base.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Converts `source` into `destination` (a PDF). `progress` receives short status lines.
    static func convert(source: URL, to destination: URL, progress: (String) -> Void) async throws -> ImportResult {
        let ext = source.pathExtension.lowercased()
        let fallbackTitle = prettyTitle(source.lastPathComponent)

        switch ext {
        case "pdf":
            guard let doc = PDFDocument(url: source) else { throw ImportError.unreadable }
            if doc.isLocked { throw ImportError.locked }
            guard doc.pageCount > 0 else { throw ImportError.unreadable }
            try FileManager.default.copyItem(at: source, to: destination)
            let attrs = doc.documentAttributes
            let title = (attrs?[PDFDocumentAttribute.titleAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle
            let author = attrs?[PDFDocumentAttribute.authorAttribute] as? String ?? ""
            return ImportResult(title: title, author: author, format: .pdf, pageCount: doc.pageCount, cover: coverFromPDF(destination))

        case "epub":
            return try await convertEPUB(source, to: destination, fallbackTitle: fallbackTitle, progress: progress)

        case "txt", "text":
            let text = try readText(source)
            let pages = try DocumentRenderer.writePDF(DocumentRenderer.plain(text), to: destination, title: fallbackTitle, author: "")
            return ImportResult(title: fallbackTitle, author: "", format: .text, pageCount: pages, cover: coverFromPDF(destination))

        case "md", "markdown":
            let text = try readText(source)
            let pages = try DocumentRenderer.writePDF(DocumentRenderer.markdown(text), to: destination, title: fallbackTitle, author: "")
            return ImportResult(title: fallbackTitle, author: "", format: .markdown, pageCount: pages, cover: coverFromPDF(destination))

        case "rtf":
            let attr = DocumentRenderer.normalize(try DocumentRenderer.rtf(data: try Data(contentsOf: source)))
            let pages = try DocumentRenderer.writePDF(attr, to: destination, title: fallbackTitle, author: "")
            return ImportResult(title: fallbackTitle, author: "", format: .rtf, pageCount: pages, cover: coverFromPDF(destination))

        case "html", "htm", "xhtml":
            let data = try Data(contentsOf: source)
            let attr = DocumentRenderer.normalize(try DocumentRenderer.html(data: data, baseURL: source.deletingLastPathComponent()))
            let pages = try DocumentRenderer.writePDF(attr, to: destination, title: fallbackTitle, author: "")
            return ImportResult(title: fallbackTitle, author: "", format: .html, pageCount: pages, cover: coverFromPDF(destination))

        case "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "webp", "bmp":
            guard let image = UIImage(contentsOfFile: source.path) else { throw ImportError.unreadable }
            try DocumentRenderer.writePDF(image: image, to: destination, title: fallbackTitle)
            return ImportResult(title: fallbackTitle, author: "", format: .image, pageCount: 1, cover: image)

        default:
            throw ImportError.unsupported(ext.isEmpty ? "unknown" : ext)
        }
    }

    // MARK: Helpers

    private static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        throw ImportError.unreadable
    }

    static func coverFromPDF(_ url: URL) -> UIImage? {
        PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 400, height: 600), for: .cropBox)
    }

    private static func convertEPUB(_ source: URL, to destination: URL, fallbackTitle: String,
                                    progress: (String) -> Void) async throws -> ImportResult {
        progress("Opening EPUB…")
        await Task.yield()
        let book = try EPUBBook.open(source)
        defer { try? FileManager.default.removeItem(at: book.directory) }

        let combined = NSMutableAttributedString()
        let total = book.chapters.count
        for (i, chapter) in book.chapters.enumerated() {
            progress("Typesetting chapter \(i + 1) of \(total)…")
            await Task.yield()
            guard let data = try? Data(contentsOf: chapter),
                  let attr = try? DocumentRenderer.html(data: data, baseURL: chapter.deletingLastPathComponent())
            else { continue }
            let normalized = DocumentRenderer.normalize(attr)
            let visible = normalized.string.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\u{FFFC}")))
            let hasImage = normalized.string.contains("\u{FFFC}")
            guard !visible.isEmpty || hasImage else { continue }
            if combined.length > 0 { combined.append(NSAttributedString(string: DocumentRenderer.chapterBreak)) }
            combined.append(normalized)
        }

        let title = book.title.isEmpty ? fallbackTitle : book.title
        progress("Binding pages…")
        await Task.yield()
        let pages = try DocumentRenderer.writePDF(combined, to: destination, title: title, author: book.author)
        var cover: UIImage?
        if let url = book.coverImageURL { cover = UIImage(contentsOfFile: url.path) }
        if cover == nil { cover = coverFromPDF(destination) }
        return ImportResult(title: title, author: book.author, format: .epub, pageCount: pages, cover: cover)
    }
}
