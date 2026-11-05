import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Pictures and PDFs, through ImageIO and PDFKit.
nonisolated enum ImageConversion {
    /// One picture into another format. Metadata and orientation carry over when the picture goes across
    /// as it is; JPEG and BMP, which can't be see-through, get a white background; icons are made square
    /// at every size their format holds.
    static func image(_ url: URL, source: ConvertSource, to target: ConvertTarget, quality: Double, into dest: URL) throws {
        guard let writer = target.imageWriter else { throw ConvertError.failed("\(target.name) isn't a picture format.") }
        let sizes = iconSizes(target)
        guard let destination = CGImageDestinationCreateWithURL(dest as CFURL, writer.identifier as CFString, max(1, sizes.count), nil)
        else { throw ConvertError.failed("Couldn't write \(dest.lastPathComponent).") }
        let lossy = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary

        if source == .svg {
            guard let picture = svgImage(url) else { throw ConvertError.unreadable(url.lastPathComponent) }
            add(picture, to: destination, target: target, sizes: sizes, options: lossy)
        } else {
            guard let file = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(file) > 0
            else { throw ConvertError.unreadable(url.lastPathComponent) }
            let properties = CGImageSourceCopyPropertiesAtIndex(file, 0, nil) as? [CFString: Any] ?? [:]
            let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false
            if sizes.isEmpty, !(hasAlpha && !keepsAlpha(target)) {
                CGImageDestinationAddImageFromSource(destination, file, 0, lossy)
            } else {
                guard let picture = upright(file, properties: properties) else { throw ConvertError.unreadable(url.lastPathComponent) }
                add(picture, to: destination, target: target, sizes: sizes, options: lossy)
            }
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: dest)
            throw ConvertError.failed("Couldn't write \(dest.lastPathComponent).")
        }
    }

    /// Each page as a picture, at twice the page's size. One page lands beside the PDF; more go in a
    /// folder named after it, one file per page.
    static func pdfPages(_ url: URL, to target: ConvertTarget, quality: Double, folder: URL, name: String) throws -> [URL] {
        guard let writer = target.imageWriter, let document = PDFDocument(url: url), document.pageCount > 0
        else { throw ConvertError.unreadable(url.lastPathComponent) }
        let count = document.pageCount
        let into = count > 1 ? try ConvertOutput.uniqueFolder(in: folder, name: name) : folder
        var made: [URL] = []
        for index in 0..<count {
            guard let page = document.page(at: index), let picture = render(page) else { continue }
            let dest = ConvertOutput.unique(in: into, name: count > 1 ? "\(name) \(index + 1)" : name, ext: target.fileExtension)
            guard let destination = CGImageDestinationCreateWithURL(dest as CFURL, writer.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, keepsAlpha(target) ? picture : flattened(picture),
                                       [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination) { made.append(dest) }
        }
        guard !made.isEmpty else { throw ConvertError.failed("Couldn't turn \(url.lastPathComponent) into pictures.") }
        return count > 1 ? [into] : made
    }

    /// The PDF's text, as plain text.
    static func pdfText(_ url: URL, to dest: URL) throws {
        guard let document = PDFDocument(url: url) else { throw ConvertError.unreadable(url.lastPathComponent) }
        try Data((document.string ?? "").utf8).write(to: dest)
    }

    /// Pictures as the pages of one PDF, in the order given.
    static func combine(_ urls: [URL], into dest: URL) throws {
        let document = PDFDocument()
        for url in urls {
            guard let picture = NSImage(contentsOf: url), let page = PDFPage(image: picture) else {
                throw ConvertError.unreadable(url.lastPathComponent)
            }
            document.insert(page, at: document.pageCount)
        }
        guard document.write(to: dest) else { throw ConvertError.failed("Couldn't write \(dest.lastPathComponent).") }
    }

    // MARK: Pieces

    /// Windows icons hold up to 256 pixels; Mac icons up to 1024.
    static func iconSizes(_ target: ConvertTarget) -> [Int] {
        switch target {
        case .ico: [256, 128, 64, 48, 32, 16]
        case .icns: [1024, 512, 256, 128, 64, 32, 16]
        default: []
        }
    }

    static func keepsAlpha(_ target: ConvertTarget) -> Bool { target != .jpeg && target != .bmp }

    private static func add(_ picture: CGImage, to destination: CGImageDestination, target: ConvertTarget, sizes: [Int], options: CFDictionary) {
        if sizes.isEmpty {
            CGImageDestinationAddImage(destination, keepsAlpha(target) ? picture : flattened(picture), options)
        } else {
            for side in sizes { if let icon = square(picture, side: side) { CGImageDestinationAddImage(destination, icon, nil) } }
        }
    }

    /// The first frame the right way up, at full size, for when it has to be redrawn.
    private static func upright(_ file: CGImageSource, properties: [CFString: Any]) -> CGImage? {
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1)]
        return CGImageSourceCreateThumbnailAtIndex(file, 0, options as CFDictionary)
    }

    /// A vector drawing as pixels: at least 1024 on its long side, sharper than its own size suggests.
    private static func svgImage(_ url: URL) -> CGImage? {
        guard let drawing = NSImage(contentsOf: url), drawing.size.width > 0, drawing.size.height > 0 else { return nil }
        let long = max(drawing.size.width, drawing.size.height)
        let scale = min(max(1024 / long, 2), 4096 / long)
        let width = Int((drawing.size.width * scale).rounded()), height = Int((drawing.size.height * scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        drawing.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// A page at twice its size on white, turned as the page says.
    private static func render(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let turned = page.rotation % 180 != 0
        let size = NSSize(width: (turned ? box.height : box.width) * 2, height: (turned ? box.width : box.height) * 2)
        let image = page.thumbnail(of: size, for: .mediaBox)
        var rect = NSRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil).map(flattened)
    }

    /// See-through parts on white, for formats without transparency.
    static func flattened(_ picture: CGImage) -> CGImage {
        guard let context = CGContext(data: nil, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return picture }
        let rect = CGRect(x: 0, y: 0, width: picture.width, height: picture.height)
        context.setFillColor(.white)
        context.fill(rect)
        context.draw(picture, in: rect)
        return context.makeImage() ?? picture
    }

    /// The picture fitted into a see-through square, for icons.
    private static func square(_ picture: CGImage, side: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let scale = min(CGFloat(side) / CGFloat(picture.width), CGFloat(side) / CGFloat(picture.height))
        let width = CGFloat(picture.width) * scale, height = CGFloat(picture.height) * scale
        context.interpolationQuality = .high
        context.draw(picture, in: CGRect(x: (CGFloat(side) - width) / 2, y: (CGFloat(side) - height) / 2, width: width, height: height))
        return context.makeImage()
    }
}
