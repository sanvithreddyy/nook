import CoreGraphics
import Foundation
import ImageIO

nonisolated enum ArtworkTint {
    struct RGB: Sendable {
        var r: Double, g: Double, b: Double
    }

    /// Average color of the artwork, with saturation kept and lightness raised so it reads on black.
    nonisolated static func average(of data: Data) -> RGB? {
        // Averaged on the CPU from a small decode: Core Image's average gives the same colour (within
        // 1/255) but brings up a GPU context, about 80 MB for a moment on every new cover.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 256,
              ] as CFDictionary)
        else { return nil }
        // The image's own color space, so its values are averaged as stored, without color management.
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var sum = (r: 0, g: 0, b: 0)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sum.r += Int(pixels[i])
            sum.g += Int(pixels[i + 1])
            sum.b += Int(pixels[i + 2])
        }
        let count = Double(width * height) * 255
        var rgb = RGB(r: Double(sum.r) / count, g: Double(sum.g) / count, b: Double(sum.b) / count)

        // Lift dark averages toward a readable lightness without washing out the hue.
        let maxChannel = max(rgb.r, rgb.g, rgb.b)
        let minChannel = min(rgb.r, rgb.g, rgb.b)
        if maxChannel - minChannel < 0.08 { return RGB(r: 0.92, g: 0.92, b: 0.92) }
        let target = 0.85
        if maxChannel < target {
            let scale = target / max(maxChannel, 0.01)
            rgb = RGB(r: min(rgb.r * scale, 1), g: min(rgb.g * scale, 1), b: min(rgb.b * scale, 1))
        }
        return rgb
    }
}
