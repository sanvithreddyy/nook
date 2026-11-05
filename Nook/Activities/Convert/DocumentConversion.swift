import AppKit
import UniformTypeIdentifiers

/// Text documents, through the text system that TextEdit uses. It reads and writes on the main
/// thread, as AppKit's HTML import requires.
@MainActor
enum DocumentConversion {
    static func convert(_ url: URL, to target: ConvertTarget, into dest: URL) throws {
        let text = try read(url)
        if target == .pdf {
            try pdf(text, to: dest)
            return
        }
        let type: NSAttributedString.DocumentType = switch target {
        case .docx: .officeOpenXML
        case .rtf: .rtf
        case .html: .html
        case .odt: .openDocument
        default: .plain
        }
        var attributes: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: type]
        if type == .plain || type == .html { attributes[.characterEncoding] = String.Encoding.utf8.rawValue }
        let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: attributes)
        try data.write(to: dest)
    }

    /// The document as styled text. Markdown keeps its line breaks, bold, italics, code and links.
    static func read(_ url: URL) throws -> NSAttributedString {
        if UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: UTType("net.daringfireball.markdown") ?? .data) == true {
            let source = try String(contentsOf: url, encoding: .utf8)
            let parsed = try AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            return styled(parsed)
        }
        do {
            return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        } catch {
            throw ConvertError.unreadable(url.lastPathComponent)
        }
    }

    /// Markdown's emphasis as fonts the text system draws.
    private static func styled(_ markdown: AttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 12)
        for run in markdown.runs {
            var font = body
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { font = .monospacedSystemFont(ofSize: 11, weight: .regular) }
            var traits: NSFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if !traits.isEmpty { font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: String(markdown[run.range].characters), attributes: attributes))
        }
        return result
    }

    /// Lays the text out on the paper size this Mac prints on, with one-inch margins, and saves the pages.
    private static func pdf(_ text: NSAttributedString, to dest: URL) throws {
        let info = NSPrintInfo(dictionary: [.jobSavingURL: dest])
        info.jobDisposition = .save
        info.paperSize = NSPrintInfo.shared.paperSize
        for edge in [\NSPrintInfo.topMargin, \.bottomMargin, \.leftMargin, \.rightMargin] { info[keyPath: edge] = 72 }
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: info.paperSize.height))
        // Paper is white whatever the Mac's appearance, and text without a colour of its own prints black.
        view.appearance = NSAppearance(named: .aqua)
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.textStorage?.setAttributedString(text)
        if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
        view.sizeToFit()
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), FileManager.default.fileExists(atPath: dest.path) else {
            throw ConvertError.failed("Couldn't make a PDF of \(dest.deletingPathExtension().lastPathComponent).")
        }
    }
}
