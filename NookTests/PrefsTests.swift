import Testing

/// Every setting belongs to exactly one area, so resetting a page or exporting settings never misses
/// or doubles one.
struct PrefsTests {
    @Test func noKeyIsInTwoAreas() {
        var seen: [String: String] = [:]
        for area in Prefs.areas {
            for key in area.defaults.keys {
                #expect(seen[key] == nil, "\(key) is in both \(seen[key] ?? "") and \(area.id)")
                seen[key] = area.id
            }
        }
    }

    @Test func areaNamesAreUnique() {
        let ids = Prefs.areas.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
