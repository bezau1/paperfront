import Foundation
import Observation

enum AppTab: Hashable {
    case books, documents
    var kind: ItemKind { self == .books ? .book : .document }
}

@MainActor
@Observable
final class Router {
    var tab: AppTab = .books
    var reading: LibraryItem?
    var showFileImporter = false
    var showURLImport = false
    var showNewDocument = false
}
