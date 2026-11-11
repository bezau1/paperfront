import UIKit

/// Turns reflowable content (text, Markdown, HTML, RTF, EPUB chapters, images)
/// into a paginated PDF so every format goes through the same reader.
enum DocumentRenderer {
    static let pageSize = CGSize(width: 432, height: 648) // 6 × 9 in, like a trade paperback
    static let margin: CGFloat = 40
    static let bodySize: CGFloat = 12.5
    static let ink = UIColor(white: 0.08, alpha: 1)
    static let chapterBreak = "\u{000C}"

    // MARK: Fonts

    static func serif(_ size: CGFloat, _ traits: UIFontDescriptor.SymbolicTraits = []) -> UIFont {
        let base = UIFont(name: "Georgia", size: size) ?? UIFont.systemFont(ofSize: size)
        return base.adding(traits)
    }

    static func mono(_ size: CGFloat) -> UIFont {
        UIFont(name: "Menlo", size: size) ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func bodyParagraph(indent: CGFloat = 0) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        p.paragraphSpacing = 7
        p.headIndent = indent
        p.firstLineHeadIndent = indent
        return p
    }

    // MARK: Plain text & Markdown

    static func plain(_ text: String, title: String? = nil) -> NSAttributedString {
        let out = NSMutableAttributedString()
        if let title, !title.isEmpty {
            let p = bodyParagraph()
            p.paragraphSpacing = 18
            out.append(NSAttributedString(string: title + "\n", attributes: [
                .font: serif(24, .traitBold), .foregroundColor: ink, .paragraphStyle: p,
            ]))
        }
        out.append(NSAttributedString(string: text, attributes: [
            .font: serif(bodySize), .foregroundColor: ink, .paragraphStyle: bodyParagraph(),
        ]))
        return out
    }

    static func markdown(_ text: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var inCode = false
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if raw.hasPrefix("```") { inCode.toggle(); continue }
            if inCode {
                out.append(NSAttributedString(string: raw + "\n", attributes: [
                    .font: mono(10.5), .foregroundColor: ink, .paragraphStyle: bodyParagraph(indent: 12),
                ]))
                continue
            }
            var line = raw
            var font = serif(bodySize)
            var para = bodyParagraph()
            var prefix = ""

            if line.hasPrefix("### ") { line.removeFirst(4); font = serif(15, .traitBold); para.paragraphSpacingBefore = 8 }
            else if line.hasPrefix("## ") { line.removeFirst(3); font = serif(18, .traitBold); para.paragraphSpacingBefore = 10 }
            else if line.hasPrefix("# ") { line.removeFirst(2); font = serif(24, .traitBold); para.paragraphSpacingBefore = 12 }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                line.removeFirst(2); prefix = "•\u{00A0}\u{00A0}"; para = bodyParagraph(indent: 16)
                para.firstLineHeadIndent = 4
            } else if line.hasPrefix("> ") {
                line.removeFirst(2); font = serif(bodySize, .traitItalic); para = bodyParagraph(indent: 16)
            } else if line.trimmingCharacters(in: .whitespaces) == "---" {
                line = "⁂"; para.alignment = .center
            }

            if !prefix.isEmpty {
                out.append(NSAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: para]))
            }
            out.append(inlineMarkdown(line, font: font, paragraph: para))
            out.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: para]))
        }
        return out
    }

    private static func inlineMarkdown(_ line: String, font: UIFont, paragraph: NSParagraphStyle) -> NSAttributedString {
        guard let parsed = try? AttributedString(
            markdown: line,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
        }
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let piece = String(parsed[run.range].characters)
            var f = font
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { f = f.adding(.traitBold) }
                if intent.contains(.emphasized) { f = f.adding(.traitItalic) }
                if intent.contains(.code) { f = mono(font.pointSize - 1.5) }
            }
            var attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: ink, .paragraphStyle: paragraph]
            if let link = run.link {
                attrs[.link] = link
                attrs[.foregroundColor] = UIColor(hex: 0x1e66f5)
            }
            out.append(NSAttributedString(string: piece, attributes: attrs))
        }
        return out
    }

    // MARK: HTML / RTF

    static func html(data: Data, baseURL: URL?) throws -> NSAttributedString {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let baseURL { options[.baseURL] = baseURL }
        return try NSAttributedString(data: data, options: options, documentAttributes: nil)
    }

    static func rtf(data: Data) throws -> NSAttributedString {
        try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }

    /// Re-skins imported rich text with the book typography and fits images to the page.
    static func normalize(_ source: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: m.length)
        let scale = bodySize / 12
        let maxImage = CGSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2 - 8)

        m.enumerateAttribute(.font, in: full) { value, range, _ in
            let old = value as? UIFont
            let traits = old?.fontDescriptor.symbolicTraits ?? []
            let size = max(8, (old?.pointSize ?? 12) * scale)
            let font: UIFont = traits.contains(.traitMonoSpace)
                ? mono(size - 1.5)
                : serif(size, traits.intersection([.traitBold, .traitItalic]))
            m.addAttribute(.font, value: font, range: range)
        }
        m.removeAttribute(.backgroundColor, range: full)
        m.addAttribute(.foregroundColor, value: ink, range: full)
        m.enumerateAttribute(.link, in: full) { value, range, _ in
            if value != nil { m.addAttribute(.foregroundColor, value: UIColor(hex: 0x1e66f5), range: range) }
        }
        m.enumerateAttribute(.paragraphStyle, in: full) { value, range, _ in
            let p = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            p.lineBreakMode = .byWordWrapping
            p.tailIndent = 0
            p.headIndent = min(max(p.headIndent, 0), 80)
            p.firstLineHeadIndent = min(max(p.firstLineHeadIndent, 0), 80)
            p.lineSpacing = max(p.lineSpacing, 3)
            p.paragraphSpacing = max(p.paragraphSpacing, 6)
            m.addAttribute(.paragraphStyle, value: p, range: range)
        }
        m.enumerateAttribute(.attachment, in: full) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            var size = attachment.bounds.size
            if size == .zero, let image = attachment.image { size = image.size }
            guard size.width > 0, size.height > 0 else { return }
            let k = min(1, maxImage.width / size.width, maxImage.height / size.height)
            attachment.bounds = CGRect(x: 0, y: 0, width: size.width * k, height: size.height * k)
        }
        return m
    }

    // MARK: Pagination

    /// Lays `text` out across 6×9" pages and writes a PDF. Returns the page count.
    @discardableResult
    static func writePDF(_ text: NSAttributedString, to url: URL, title: String, author: String) throws -> Int {
        let textSize = CGSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        var containers: [NSTextContainer] = []
        while containers.count < 4000 {
            let c = NSTextContainer(size: textSize)
            c.lineFragmentPadding = 0
            layout.addTextContainer(c)
            containers.append(c)
            let range = layout.glyphRange(for: c)
            if range.length == 0 {
                containers.removeLast()
                layout.removeTextContainer(at: containers.count)
                break
            }
            if NSMaxRange(range) >= layout.numberOfGlyphs { break }
        }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextAuthor as String: author,
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        try renderer.writePDF(to: url) { ctx in
            if containers.isEmpty {
                ctx.beginPage()
                return
            }
            for container in containers {
                ctx.beginPage()
                let range = layout.glyphRange(for: container)
                let origin = CGPoint(x: margin, y: margin)
                layout.drawBackground(forGlyphRange: range, at: origin)
                layout.drawGlyphs(forGlyphRange: range, at: origin)
            }
        }
        return max(1, containers.count)
    }

    /// A single page the size of the picture.
    static func writePDF(image: UIImage, to url: URL, title: String) throws {
        var size = image.size
        let longest = max(size.width, size.height)
        if longest > 1200 { let k = 1200 / longest; size = CGSize(width: size.width * k, height: size.height * k) }
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size), format: format)
        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension UIFont {
    func adding(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard !traits.isEmpty,
              let d = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else { return self }
        return UIFont(descriptor: d, size: pointSize)
    }
}
