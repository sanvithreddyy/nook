import SwiftUI

/// The island outline: concave "ears" where it meets the top edge, smoothed (squircle-like) bottom corners.
/// Drawn as one closed outline so there is no anti-aliasing seam between the ears and the body.
/// As a pill (screens without a notch) it floats free of the top edge like Apple's own Mac island: the
/// same body, every corner round, and no ears.
nonisolated struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var pill = false

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let ear = max(0, min(topRadius, w / 4, h / 2))
        if pill {
            let body = rect.insetBy(dx: ear, dy: 0)
            return RoundedRectangle(cornerRadius: max(0, min(bottomRadius, body.height / 2, body.width / 2)), style: .continuous).path(in: body)
        }
        let bodyWidth = w - ear * 2
        // A smoothed corner starts 1.5 radii from the corner; the control points sit close to it,
        // so curvature ramps up from zero instead of jumping like a circular arc.
        let reach = max(0, min(bottomRadius * 1.5, bodyWidth / 2, h - ear))
        let handle = reach * 0.2333

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + ear, y: rect.minY + ear),
                       control: CGPoint(x: rect.minX + ear, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - reach))
        p.addCurve(to: CGPoint(x: rect.minX + ear + reach, y: rect.maxY),
                   control1: CGPoint(x: rect.minX + ear, y: rect.maxY - handle),
                   control2: CGPoint(x: rect.minX + ear + handle, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - ear - reach, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.maxX - ear, y: rect.maxY - reach),
                   control1: CGPoint(x: rect.maxX - ear - handle, y: rect.maxY),
                   control2: CGPoint(x: rect.maxX - ear, y: rect.maxY - handle))
        p.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - ear, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
