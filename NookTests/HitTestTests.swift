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

    /// The meeting drop sits right of the island, clear of it, and takes the pointer at the top edge too.
    @Test func theMeetingDropIsItsOwnTarget() {
        let drop = NotchWindowController.companionRect(island: island, drop: CGSize(width: 40, height: 32), in: panel)
        let islandRect = NotchWindowController.hitRect(for: island, presentation: .activity(.nowPlaying), in: panel)
        #expect(drop.contains(CGPoint(x: drop.midX, y: panel.maxY)))
        #expect(drop.minX > panel.midX + island.size.width / 2)
        #expect(!islandRect.contains(CGPoint(x: drop.midX, y: panel.maxY - 10)))
    }

    @Test func besideTheIslandIsOutside() {
        let rect = NotchWindowController.hitRect(for: island, presentation: .idle, in: panel)
        #expect(!rect.contains(CGPoint(x: panel.midX + 150, y: panel.maxY)))
        #expect(!rect.contains(CGPoint(x: panel.midX, y: panel.maxY - 60)))
    }
}
