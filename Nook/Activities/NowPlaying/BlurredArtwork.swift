import CoreImage
import Foundation

/// The artwork blurred, saturated and darkened once per track, so the expanded island only draws an image.
nonisolated enum BlurredArtwork {
    /// Wraps the result for the hop back to the main actor.
    struct Image: @unchecked Sendable {
        let cgImage: CGImage
    }

    nonisolated static func render(_ data: Data) -> Image? {
        guard let source = CIImage(data: data), source.extent.width > 0 else { return nil }
        // Blur a small copy: the result is soft anyway, and it's drawn about 420 pt wide.
        let scale = 160 / source.extent.width
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = small.extent
        let output = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 9)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5])
            // Darken so white text stays readable on light covers.
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.62, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.62, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.62, w: 0),
            ])
            .cropped(to: extent)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(output, from: extent).map(Image.init)
    }
}
