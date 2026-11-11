import UIKit
import Observation

@MainActor
@Observable
final class LibraryStore {
    var items: [LibraryItem] = []
    var importStatus: String?
    var errorMessage: String?

    @ObservationIgnored private let rootURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let coverCache = NSCache<NSString, UIImage>()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootURL = support.appendingPathComponent("PaperFront", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL.appendingPathComponent("Items"), withIntermediateDirectories: true)
        load()
    }

    // MARK: Paths

    func directory(for id: UUID) -> URL { rootURL.appendingPathComponent("Items/\(id.uuidString)", isDirectory: true) }
    func pdfURL(for item: LibraryItem) -> URL { directory(for: item.id).appendingPathComponent("book.pdf") }
    func annotationsURL(for item: LibraryItem) -> URL { directory(for: item.id).appendingPathComponent("annotations.json") }
    private func coverURL(for id: UUID) -> URL { directory(for: id).appendingPathComponent("cover.jpg") }
    private var libraryURL: URL { rootURL.appendingPathComponent("library.json") }

    func cover(for item: LibraryItem) -> UIImage? {
        let key = item.id.uuidString as NSString
        if let cached = coverCache.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: coverURL(for: item.id).path) else { return nil }
        coverCache.setObject(image, forKey: key)
        return image
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: libraryURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([LibraryItem].self, from: data)) ?? []
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) { try? data.write(to: libraryURL, options: .atomic) }
    }

    // MARK: Editing

    func item(id: UUID) -> LibraryItem? { items.first { $0.id == id } }

    func rename(_ item: LibraryItem, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].title = t
        scheduleSave()
    }

    func move(_ item: LibraryItem, to kind: ItemKind) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].kind = kind
        scheduleSave()
    }

    func delete(_ item: LibraryItem) {
        try? FileManager.default.removeItem(at: directory(for: item.id))
        items.removeAll { $0.id == item.id }
        coverCache.removeObject(forKey: item.id.uuidString as NSString)
        scheduleSave()
    }

    func recordOpened(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].lastOpenedAt = Date()
        scheduleSave()
    }

    func recordProgress(_ id: UUID, page: Int, pageCount: Int? = nil) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].lastPage = page
        if let pageCount { items[i].pageCount = pageCount }
        scheduleSave()
    }

    /// Replaces the stored PDF (used when the annotation layer is baked in).
    func replacePDF(of item: LibraryItem, with newFile: URL) throws {
        let dest = pdfURL(for: item)
        _ = try FileManager.default.replaceItemAt(dest, withItemAt: newFile)
    }

    // MARK: Import

    func importFiles(_ urls: [URL], kind: ItemKind) async {
        for url in urls { await importFile(url, kind: kind) }
    }

    func importFile(_ url: URL, kind: ItemKind, sourceURL: String? = nil) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        importStatus = "Importing \(DocumentImporter.prettyTitle(url.lastPathComponent))…"
        defer { importStatus = nil }

        let id = UUID()
        let dir = directory(for: id)
        var staging: URL?
        do {
            staging = try stage(url)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let result = try await DocumentImporter.convert(
                source: staging!,
                to: dir.appendingPathComponent("book.pdf"),
                progress: { [weak self] in self?.importStatus = $0 }
            )
            if let cover = result.cover, let jpeg = cover.jpegData(compressionQuality: 0.85) {
                try? jpeg.write(to: coverURL(for: id))
            }
            let item = LibraryItem(
                id: id, title: result.title, author: result.author, kind: kind,
                format: result.format, pageCount: result.pageCount, sourceURL: sourceURL
            )
            items.append(item)
            scheduleSave()
        } catch {
            try? FileManager.default.removeItem(at: dir)
            errorMessage = error.localizedDescription
        }
        if let staging { try? FileManager.default.removeItem(at: staging.deletingLastPathComponent()) }
    }

    /// Copies a (possibly iCloud / security-scoped) file somewhere we fully own.
    private func stage(_ url: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readURL in
            do { try FileManager.default.copyItem(at: readURL, to: dest) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        return dest
    }

    func importFromWeb(_ raw: String, kind: ItemKind) async {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard var comps = URLComponents(string: text), comps.host?.isEmpty == false else {
            errorMessage = ImportError.badURL.localizedDescription
            return
        }
        if comps.scheme == "http" { comps.scheme = "https" }
        guard let url = comps.url else {
            errorMessage = ImportError.badURL.localizedDescription
            return
        }

        importStatus = "Downloading…"
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            let (tmp, response) = try await URLSession.shared.download(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ImportError.http(http.statusCode)
            }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("download-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let staged = dir.appendingPathComponent(Self.filename(for: response, url: url))
            try FileManager.default.moveItem(at: tmp, to: staged)
            await importFile(staged, kind: kind, sourceURL: url.absoluteString)
        } catch {
            importStatus = nil
            errorMessage = error.localizedDescription
        }
    }

    private static func filename(for response: URLResponse, url: URL) -> String {
        var name = response.suggestedFilename ?? url.lastPathComponent
        if name.isEmpty || name == "/" { name = url.host ?? "download" }
        if (name as NSString).pathExtension.isEmpty {
            let mime = (response.mimeType ?? "").lowercased()
            let ext: String
            switch mime {
            case "application/pdf": ext = "pdf"
            case "application/epub+zip": ext = "epub"
            case "text/plain": ext = "txt"
            case "text/markdown": ext = "md"
            case "text/html", "application/xhtml+xml": ext = "html"
            case "application/rtf", "text/rtf": ext = "rtf"
            case "image/png": ext = "png"
            case "image/jpeg": ext = "jpg"
            default: ext = "html"
            }
            name += ".\(ext)"
        }
        return name.replacingOccurrences(of: "/", with: "_")
    }

    // MARK: New document

    func createDocument(title: String, text: String) async {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = t.isEmpty ? "Untitled" : t
        let id = UUID()
        let dir = directory(for: id)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let pdf = dir.appendingPathComponent("book.pdf")
            let pages = try DocumentRenderer.writePDF(
                DocumentRenderer.plain(text, title: name), to: pdf, title: name, author: ""
            )
            if let cover = DocumentImporter.coverFromPDF(pdf), let jpeg = cover.jpegData(compressionQuality: 0.85) {
                try? jpeg.write(to: coverURL(for: id))
            }
            items.append(LibraryItem(id: id, title: name, kind: .document, format: .text, pageCount: pages))
            scheduleSave()
        } catch {
            try? FileManager.default.removeItem(at: dir)
            errorMessage = error.localizedDescription
        }
    }
}
