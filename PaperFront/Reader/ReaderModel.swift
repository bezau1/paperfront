import PDFKit
import PencilKit
import Observation

@MainActor
@Observable
final class ReaderModel {
    private(set) var item: LibraryItem
    var document: PDFDocument
    let annotations: AnnotationStore
    @ObservationIgnored let store: LibraryStore

    var config = ReaderConfig()
    var currentPage: Int
    var chromeVisible = true
    var highlightActionID: UUID?
    private(set) var historyTick = 0

    @ObservationIgnored weak var controller: PageCurlController?

    init?(item: LibraryItem, store: LibraryStore) {
        guard let doc = PDFDocument(url: store.pdfURL(for: item)), doc.pageCount > 0 else { return nil }
        self.item = item
        self.store = store
        document = doc
        annotations = AnnotationStore(fileURL: store.annotationsURL(for: item))
        currentPage = min(max(item.lastPage, 0), doc.pageCount - 1)
        config.night = UserDefaults.standard.object(forKey: "reader.night") as? Bool ?? true
        store.recordOpened(item.id)
        store.recordProgress(item.id, page: currentPage, pageCount: doc.pageCount)
    }

    var pageCount: Int { document.pageCount }

    var pageLabel: String {
        if controller?.isTwoPage == true, currentPage + 2 <= pageCount {
            return "Pages \(currentPage + 1)–\(currentPage + 2) of \(pageCount)"
        }
        return "Page \(currentPage + 1) of \(pageCount)"
    }

    var canUndo: Bool { _ = historyTick; return controller?.canUndo ?? false }
    var canRedo: Bool { _ = historyTick; return controller?.canRedo ?? false }

    func touchHistory() { historyTick += 1 }

    func pageDidChange(_ index: Int) {
        guard index != currentPage else { return }
        currentPage = index
        store.recordProgress(item.id, page: index)
        touchHistory()
    }

    func goTo(_ page: Int, animated: Bool = true) { controller?.goTo(page, animated: animated) }

    func close() {
        annotations.saveNow()
        store.saveNow()
    }

    // MARK: Outline

    struct OutlineRow: Identifiable {
        let id = UUID()
        let title: String
        let page: Int
        let depth: Int
    }

    var outline: [OutlineRow] {
        var rows: [OutlineRow] = []
        func walk(_ node: PDFOutline, depth: Int) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                if let page = child.destination?.page {
                    let index = document.index(for: page)
                    if index != NSNotFound { rows.append(OutlineRow(title: child.label ?? "Untitled", page: index, depth: depth)) }
                }
                walk(child, depth: depth + 1)
            }
        }
        if let root = document.outlineRoot { walk(root, depth: 0) }
        return rows
    }

    // MARK: Export / bake

    func exportAnnotatedCopy() throws -> URL {
        let safe = item.title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe) (annotated).pdf")
        try? FileManager.default.removeItem(at: url)
        try PDFExporter.write(document: document, annotations: annotations, to: url)
        return url
    }

    /// Permanently merges the annotation layer into this library copy of the file.
    func bakeIntoLibraryCopy() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bake-\(UUID().uuidString).pdf")
        try PDFExporter.write(document: document, annotations: annotations, to: tmp)
        try store.replacePDF(of: item, with: tmp)
        guard let fresh = PDFDocument(url: store.pdfURL(for: item)) else { return }
        document = fresh
        annotations.clearAll()
        annotations.saveNow()
        controller?.reload()
    }

    func clearAnnotations() {
        annotations.clearAll()
        annotations.saveNow()
        controller?.reload()
    }
}
