import Foundation
import Observation

/// The "secret layer": highlights and ink are kept in a sidecar JSON file and
/// drawn on top of the document. The document itself is never modified unless
/// the user explicitly exports or bakes the layer into it.
@MainActor
@Observable
final class AnnotationStore {
    private(set) var highlights: [Highlight] = []
    private var drawings: [String: Data] = [:]

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Called whenever highlights change so visible pages can redraw.
    @ObservationIgnored var onHighlightsChanged: (() -> Void)?

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let file = try? JSONDecoder().decode(AnnotationFile.self, from: data) {
            highlights = file.highlights
            drawings = file.drawings
        }
    }

    var isEmpty: Bool { highlights.isEmpty && drawings.isEmpty }
    var drawnPages: [Int] { drawings.keys.compactMap(Int.init).sorted() }

    func highlights(onPage page: Int) -> [Highlight] {
        highlights.filter { $0.page == page }
    }

    func drawingData(page: Int) -> Data? { drawings[String(page)] }

    // MARK: Mutations

    func add(_ highlight: Highlight) {
        highlights.append(highlight)
        changed()
    }

    func removeHighlight(id: UUID) {
        highlights.removeAll { $0.id == id }
        changed()
    }

    func setNote(_ note: String, for id: UUID) {
        guard let i = highlights.firstIndex(where: { $0.id == id }) else { return }
        highlights[i].note = note
        changed()
    }

    func setColor(_ color: Swatch, for id: UUID) {
        guard let i = highlights.firstIndex(where: { $0.id == id }) else { return }
        highlights[i].color = color
        changed()
    }

    func setDrawing(_ data: Data?, page: Int) {
        if let data { drawings[String(page)] = data } else { drawings.removeValue(forKey: String(page)) }
        scheduleSave()
    }

    func clearAll() {
        highlights = []
        drawings = [:]
        changed()
    }

    // MARK: Persistence

    private func changed() {
        onHighlightsChanged?()
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        let file = AnnotationFile(highlights: highlights, drawings: drawings)
        if isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
