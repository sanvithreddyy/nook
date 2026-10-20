import CoreImage
import Foundation

nonisolated enum ArtworkTint {
    struct RGB: Sendable {
        var r: Double, g: Double, b: Double
    }

    /// Average color of the artwork, with saturation kept and lightness raised so it reads on black.
    nonisolated static func average(of data: Data) -> RGB? {
        guard let image = CIImage(data: data) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: image.extent),
        ])
        guard let output = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        var rgb = RGB(r: Double(pixel[0]) / 255, g: Double(pixel[1]) / 255, b: Double(pixel[2]) / 255)

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
