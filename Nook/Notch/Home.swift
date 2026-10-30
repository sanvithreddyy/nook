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
    /// The modules that are on, in their order.
    var modules: [HomeModule] = HomeModule.allCases
    var size: HomeSize = .medium

    var perPage: Int { layout == .oneAtATime ? 1 : max(columns, 1) }
    var scale: CGFloat { size.scale }

    static var current: HomeConfig {
        let defaults = UserDefaults.standard
        let hidden = Set(HomeOrder.parse(defaults.string(forKey: Prefs.homeHidden) ?? ""))
        return HomeConfig(
            layout: HomeLayout(rawValue: defaults.string(forKey: Prefs.homeLayout) ?? "") ?? .sideBySide,
            columns: min(max(defaults.integer(forKey: Prefs.homeColumns), 2), 3),
            modules: HomeOrder.saved.filter { !hidden.contains($0) },
            size: HomeSize(rawValue: defaults.string(forKey: Prefs.homeSize) ?? "") ?? .medium)
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
