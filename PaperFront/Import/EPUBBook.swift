import UIKit

struct EPUBBook {
    var title: String
    var author: String
    /// Absolute file URLs (inside `directory`) of spine documents, in reading order.
    var chapters: [URL]
    var coverImageURL: URL?
    /// Temp directory the archive was extracted to. Caller deletes it.
    var directory: URL

    enum EPUBError: LocalizedError {
        case missingPackage, empty
        var errorDescription: String? {
            switch self {
            case .missingPackage: return "This EPUB has no readable package file."
            case .empty: return "This EPUB doesn't contain any chapters."
            }
        }
    }

    static func open(_ file: URL) throws -> EPUBBook {
        let zip = try MiniZip(data: try Data(contentsOf: file, options: .mappedIfSafe))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("epub-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        do {
            for entry in zip.entries where !entry.name.hasSuffix("/") {
                let parts = entry.name.split(separator: "/").map(String.init)
                guard !parts.contains(".."), !entry.name.hasPrefix("/") else { continue }
                let dest = dir.appendingPathComponent(entry.name)
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try zip.read(entry).write(to: dest)
            }

            let container = dir.appendingPathComponent("META-INF/container.xml")
            guard let containerData = try? Data(contentsOf: container) else { throw EPUBError.missingPackage }
            let rootParser = AttributeCollector(element: "rootfile")
            rootParser.run(containerData)
            guard let opfPath = rootParser.found.first?["full-path"] else { throw EPUBError.missingPackage }
            let opfURL = dir.appendingPathComponent(opfPath)
            guard let opfData = try? Data(contentsOf: opfURL) else { throw EPUBError.missingPackage }

            let opf = OPFParser()
            opf.run(opfData)
            let base = opfURL.deletingLastPathComponent()

            func resolve(_ href: String) -> URL {
                let decoded = href.removingPercentEncoding ?? href
                let clean = decoded.components(separatedBy: "#")[0]
                return base.appendingPathComponent(clean)
            }

            let chapters = opf.spine.compactMap { opf.manifest[$0] }.map { resolve($0.href) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !chapters.isEmpty else { throw EPUBError.empty }

            var cover: URL?
            if let item = opf.manifest.values.first(where: { $0.properties.contains("cover-image") }) {
                cover = resolve(item.href)
            } else if let id = opf.coverID, let item = opf.manifest[id] {
                cover = resolve(item.href)
            }

            return EPUBBook(
                title: opf.title.trimmingCharacters(in: .whitespacesAndNewlines),
                author: opf.creators.joined(separator: ", "),
                chapters: chapters,
                coverImageURL: cover,
                directory: dir
            )
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
    }
}

// MARK: - XML helpers

private func localName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init) ?? name
}

private final class AttributeCollector: NSObject, XMLParserDelegate {
    let element: String
    var found: [[String: String]] = []
    init(element: String) { self.element = element }

    func run(_ data: Data) {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if localName(elementName) == element { found.append(attributeDict) }
    }
}

private final class OPFParser: NSObject, XMLParserDelegate {
    struct Item { var href: String; var type: String; var properties: String }

    var title = ""
    var creators: [String] = []
    var manifest: [String: Item] = [:]
    var spine: [String] = []
    var coverID: String?

    private var current = ""
    private var text = ""

    func run(_ data: Data) {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        current = localName(elementName)
        text = ""
        switch current {
        case "item":
            if let id = a["id"], let href = a["href"] {
                manifest[id] = Item(href: href, type: a["media-type"] ?? "", properties: a["properties"] ?? "")
            }
        case "itemref":
            if let idref = a["idref"] { spine.append(idref) }
        case "meta":
            if a["name"] == "cover", let c = a["content"] { coverID = c }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = localName(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "title", title.isEmpty, !value.isEmpty { title = value }
        if name == "creator", !value.isEmpty { creators.append(value) }
        text = ""
    }
}
