import SwiftUI

/// What the open island's home is made of: each drawn the way Apple already draws it (the Music card,
/// and the Calendar, Batteries, Weather, Reminders, World Clock, Shortcuts and Timer widgets).
enum HomeModule: String, CaseIterable, Identifiable, Hashable {
    case music, calendar, batteries, weather, reminders, clock, shortcuts, timer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: "Music"
        case .calendar: "Calendar"
        case .batteries: "Batteries"
        case .weather: "Weather"
        case .reminders: "Reminders"
        case .clock: "World Clock"
        case .shortcuts: "Shortcuts"
        case .timer: "Timer"
        }
    }

    /// Whether it can take more than its own width when its page is narrower than the island; the
    /// Music card keeps its shape.
    var stretches: Bool { self != .music }
}

/// Side by side: several modules open together in one wide island. One at a time: a narrow island
/// with one module per page, swiped through.
enum HomeLayout: String, CaseIterable, Identifiable {
    case sideBySide, oneAtATime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sideBySide: "Side by Side"
        case .oneAtATime: "One at a Time"
        }
    }
}

/// Everything on a home page scales together, so a larger home is a larger island, not looser spacing.
enum HomeSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: 0.88
        case .medium: 1
        case .large: 1.14
        }
    }
}

/// The home as Settings has it.
struct HomeConfig: Equatable {
    var layout: HomeLayout = .sideBySide
    /// Modules on one page when side by side.
    var columns = 2
    /// Every module in its order, for the automatic pages.
    var order: [HomeModule] = HomeModule.allCases
    /// Modules turned off.
    var hidden: Set<HomeModule> = []
    /// Pages arranged in Settings; nil until they are, when the modules fill pages in order.
    var saved: HomeArrangement?
    var size: HomeSize = .medium

    var perPage: Int { layout == .oneAtATime ? 1 : max(columns, 1) }
    var scale: CGFloat { size.scale }

    /// The pages: as arranged, or the modules in order a page at a time, with the shelf last.
    var arrangement: HomeArrangement {
        (saved ?? HomeArrangement(pages: [.modules(order), .shelf])).normalized(hidden: hidden, perPage: perPage)
    }

    /// The modules that are on, in page order.
    var modules: [HomeModule] { arrangement.pages.flatMap(\.modules).filter { !hidden.contains($0) } }

    static var current: HomeConfig {
        let defaults = UserDefaults.standard
        return HomeConfig(
            layout: HomeLayout(rawValue: defaults.string(forKey: Prefs.homeLayout) ?? "") ?? .sideBySide,
            columns: min(max(defaults.integer(forKey: Prefs.homeColumns), 2), 3),
            order: HomeOrder.saved,
            hidden: Set(HomeOrder.parse(defaults.string(forKey: Prefs.homeHidden) ?? "")),
            saved: HomeArrangement.parse(defaults.string(forKey: Prefs.homePages) ?? ""),
            size: HomeSize(rawValue: defaults.string(forKey: Prefs.homeSize) ?? "") ?? .medium)
    }
}

/// The open island's pages as Settings arranges them: modules grouped onto pages, and the shelf
/// (AirDrop and files) as a page of its own wherever it's placed, first to swipe to it from the left.
/// Saved as "music,calendar|shelf|batteries,weather".
struct HomeArrangement: Equatable {
    enum Page: Hashable {
        case modules([HomeModule])
        case shelf

        var modules: [HomeModule] {
            if case .modules(let modules) = self { modules } else { [] }
        }
    }

    var pages: [Page]

    static func parse(_ text: String) -> HomeArrangement? {
        let pages = text.split(separator: "|").compactMap { part -> Page? in
            if part == "shelf" { return .shelf }
            let modules = HomeOrder.parse(String(part))
            return modules.isEmpty ? nil : .modules(modules)
        }
        return pages.isEmpty ? nil : HomeArrangement(pages: pages)
    }

    var string: String {
        pages.map { $0 == .shelf ? "shelf" : HomeOrder.string($0.modules) }.joined(separator: "|")
    }

    /// Every module once and the shelf once, and no page with more modules on than `perPage`: the rest
    /// carry on in a page after it. Modules that are off take no room. Modules it doesn't know yet (from
    /// a later version) get pages of their own after the last page of modules.
    func normalized(hidden: Set<HomeModule>, perPage: Int) -> HomeArrangement {
        let room = max(perPage, 1)
        var seen = Set<HomeModule>()
        var result: [Page] = []
        for page in pages {
            switch page {
            case .shelf:
                if !result.contains(.shelf) { result.append(.shelf) }
            case .modules(let modules):
                var current: [HomeModule] = []
                var on = 0
                for module in modules where seen.insert(module).inserted {
                    let isOn = !hidden.contains(module)
                    if isOn, on == room {
                        result.append(.modules(current))
                        current = []
                        on = 0
                    }
                    current.append(module)
                    if isOn { on += 1 }
                }
                if !current.isEmpty { result.append(.modules(current)) }
            }
        }
        let missing = HomeModule.allCases.filter { !seen.contains($0) }.map { Page.modules([$0]) }
        let after = (result.lastIndex { $0 != .shelf } ?? -1) + 1
        result.insert(contentsOf: missing, at: after)
        if !result.contains(.shelf) { result.append(.shelf) }
        return HomeArrangement(pages: result)
    }

    /// The island's pages: on each, the modules `showing` says have something to show; pages left
    /// empty are left out.
    func pages(showing: (HomeModule) -> Bool) -> [Page] {
        pages.compactMap { page in
            guard case .modules(let modules) = page else { return page }
            let shown = modules.filter(showing)
            return shown.isEmpty ? nil : .modules(shown)
        }
    }

    // MARK: Editing, as Settings drags things about

    /// Drops a module on another: in the same page it takes that place; on another page it goes in
    /// beside it if there's room, and swaps with it if the page is full.
    mutating func move(_ module: HomeModule, onto target: HomeModule, hidden: Set<HomeModule>, perPage: Int) {
        guard module != target, let from = location(of: module), let to = location(of: target) else { return }
        var source = pages[from.page].modules
        var destination = pages[to.page].modules
        if from.page == to.page {
            source.move(fromOffsets: IndexSet(integer: from.index), toOffset: to.index > from.index ? to.index + 1 : to.index)
            pages[from.page] = .modules(source)
        } else if hidden.contains(module) || hasRoom(destination, hidden: hidden, perPage: perPage) {
            source.remove(at: from.index)
            destination.insert(module, at: to.index)
            pages[from.page] = .modules(source)
            pages[to.page] = .modules(destination)
        } else {
            source[from.index] = target
            destination[to.index] = module
            pages[from.page] = .modules(source)
            pages[to.page] = .modules(destination)
        }
        dropEmptyPages()
    }

    /// Drops a module on a page's title: to the end of that page, if there's room.
    mutating func move(_ module: HomeModule, toPage page: Int, hidden: Set<HomeModule>, perPage: Int) {
        guard let from = location(of: module), from.page != page, pages.indices.contains(page), pages[page] != .shelf else { return }
        let destination = pages[page].modules
        guard hidden.contains(module) || hasRoom(destination, hidden: hidden, perPage: perPage) else { return }
        var source = pages[from.page].modules
        source.remove(at: from.index)
        pages[from.page] = .modules(source)
        pages[page] = .modules(destination + [module])
        dropEmptyPages()
    }

    /// A page of its own, last.
    mutating func moveToNewPage(_ module: HomeModule) {
        guard let from = location(of: module) else { return }
        var source = pages[from.page].modules
        source.remove(at: from.index)
        pages[from.page] = .modules(source)
        pages.append(.modules([module]))
        dropEmptyPages()
    }

    /// Moves a whole page (the shelf among them) to where another one is.
    mutating func movePage(_ from: Int, to: Int) {
        guard from != to, pages.indices.contains(from), pages.indices.contains(to) else { return }
        pages.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    /// Moves a whole page to the end.
    mutating func movePageToEnd(_ from: Int) {
        guard pages.indices.contains(from), from != pages.count - 1 else { return }
        pages.append(pages.remove(at: from))
    }

    func hasRoom(_ page: [HomeModule], hidden: Set<HomeModule>, perPage: Int) -> Bool {
        page.filter { !hidden.contains($0) }.count < max(perPage, 1)
    }

    private func location(of module: HomeModule) -> (page: Int, index: Int)? {
        for (page, content) in pages.enumerated() {
            if let index = content.modules.firstIndex(of: module) { return (page, index) }
        }
        return nil
    }

    private mutating func dropEmptyPages() {
        pages.removeAll { $0 != .shelf && $0.modules.isEmpty }
    }
}

/// The modules' order, saved as "music,calendar,batteries". Modules missing from the saved list
/// (added in a later version) go at the end.
enum HomeOrder {
    static func parse(_ text: String) -> [HomeModule] {
        text.split(separator: ",").compactMap { HomeModule(rawValue: String($0)) }
    }

    static func string(_ modules: [HomeModule]) -> String {
        modules.map(\.rawValue).joined(separator: ",")
    }

    static var saved: [HomeModule] {
        var order: [HomeModule] = []
        for module in parse(UserDefaults.standard.string(forKey: Prefs.homeOrder) ?? "") + HomeModule.allCases where !order.contains(module) {
            order.append(module)
        }
        return order
    }
}

/// Measurements of a home page at medium size: 20 pt from the island's
/// edge, 24 between modules, the modules 152 tall starting 10 below the notch line.
enum HomeMetrics {
    static let inset: CGFloat = 20
    static let gap: CGFloat = 24
    static let below: CGFloat = 10
    static let height: CGFloat = 152
    static let bottom: CGFloat = 18
    /// One battery ring with its level.
    static let batteryCell: CGFloat = 76
    /// Rings the Batteries widget always shows, empty ones holding the places, as Apple's does.
    static let batterySlots = 4
    /// The Batteries widget shows at most this many devices.
    static let maxBatteries = 5

    static func width(_ module: HomeModule, batteries: Int) -> CGFloat {
        switch module {
        case .music, .reminders, .shortcuts, .timer: 300
        case .calendar, .weather, .clock: 320
        case .batteries: CGFloat(min(max(batteries, batterySlots), maxBatteries)) * batteryCell
        }
    }

    /// A page's body: as wide as its modules, ears left out; its height below the notch line.
    static func pageSize(_ modules: [HomeModule], batteries: Int, scale: CGFloat) -> CGSize {
        let widths = modules.map { width($0, batteries: batteries) }.reduce(0, +)
        let gaps = gap * CGFloat(max(modules.count - 1, 0))
        return CGSize(width: ((inset * 2) + widths + gaps) * scale, height: (below + height + bottom) * scale)
    }

    /// The widest page this home can show, for sizing the panel.
    static func widestPage(_ config: HomeConfig) -> CGSize {
        let widest = HomeModule.allCases.sorted { width($0, batteries: maxBatteries) > width($1, batteries: maxBatteries) }
        return pageSize(Array(widest.prefix(config.perPage)), batteries: maxBatteries, scale: config.scale)
    }
}

extension EnvironmentValues {
    /// The home's size, applied to every measurement in a module.
    @Entry var homeScale: CGFloat = 1
}

/// One page of the home: its modules side by side, each at its own width.
struct HomePage: View {
    @Environment(NotchModel.self) private var model
    let modules: [HomeModule]

    var body: some View {
        let k = model.home.scale
        // On a page narrower than the island, the modules that can stretch share the rest of the
        // width rather than leaving it empty either side.
        let spare = max(model.openBody.width - HomeMetrics.pageSize(modules, batteries: model.batteryCount, scale: k).width, 0)
        let extra = spare / CGFloat(max(modules.filter(\.stretches).count, 1))
        HStack(alignment: .top, spacing: HomeMetrics.gap * k) {
            ForEach(modules) { module in
                let width = HomeMetrics.width(module, batteries: model.batteryCount) * k + (module.stretches ? extra : 0)
                Group {
                    switch module {
                    case .music: MusicModule()
                    case .calendar: CalendarModule()
                    case .batteries: BatteriesModule(width: width)
                    case .weather: WeatherModule()
                    case .reminders: RemindersModule()
                    case .clock: ClockModule()
                    case .shortcuts: ShortcutsModule()
                    case .timer: TimerModule()
                    }
                }
                .frame(width: width, height: HomeMetrics.height * k, alignment: .topLeading)
            }
        }
        .padding(.top, model.notch.size.height + HomeMetrics.below * k)
        // In the middle when another page sets a wider island.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.homeScale, k)
    }
}

/// Small red capitals over a module's content, as the Calendar widget heads its day and month.
struct ModuleHeading: View {
    @Environment(\.homeScale) private var k
    let text: String
    var color: Color = .red

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11 * k, weight: .semibold))
            .tracking(0.44 * k)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
