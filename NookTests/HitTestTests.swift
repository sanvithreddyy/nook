import AppKit
import Testing


/// The pointer pushed against the top of the screen reports y == the screen's maxY.
/// That edge is where the notch is, so it has to count as inside the island.
@MainActor
struct HitTestTests {
    let panel = CGRect(x: 0, y: 682, width: 800, height: 300)
    let island = IslandLayout(size: CGSize(width: 200, height: 32), topRadius: 6, bottomRadius: 10)

    @Test(arguments: [Presentation.idle, .expanded, .activity(.nowPlaying)])
    func theTopEdgeIsInside(_ presentation: Presentation) {
        let rect = NotchWindowController.hitRect(for: island, presentation: presentation, in: panel)
        #expect(rect.contains(CGPoint(x: panel.midX, y: panel.maxY)))
    }

    @Test func besideTheIslandIsOutside() {
        let rect = NotchWindowController.hitRect(for: island, presentation: .idle, in: panel)
        #expect(!rect.contains(CGPoint(x: panel.midX + 150, y: panel.maxY)))
        #expect(!rect.contains(CGPoint(x: panel.midX, y: panel.maxY - 60)))
    }
}
