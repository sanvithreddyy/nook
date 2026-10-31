import SwiftUI

/// The open island's home: how its modules sit, how big it is, which modules show and in what order,
/// and each module's own options. Changes show on the real island while "Preview on the notch" is on.
struct HomePane: View {
    @AppStorage(Prefs.homeLayout) private var layout = HomeLayout.sideBySide
    @AppStorage(Prefs.homeColumns) private var columns = 2
    @AppStorage(Prefs.homeSize) private var size = HomeSize.medium
    @AppStorage(Prefs.homeOrder) private var orderText = HomeOrder.string(HomeModule.allCases)
    @AppStorage(Prefs.homeHidden) private var hiddenText = ""

    var body: some View {
        SettingsPage(title: "Home", area: Prefs.homeArea,
                     preview: "Keeps the island open while you change things here, with what's playing and your real events.") {
            SettingsSection("Layout") {
                HomeLayoutPicker(selection: $layout)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                SettingsRow("Modules side by side") {
                    Picker("Modules side by side", selection: $columns) {
                        Text("Two").tag(2)
                        Text("Three").tag(3)
                    }
                    .segmentedStyle()
                }
                .disabled(layout == .oneAtATime)
                SettingsRow("Size") {
                    Picker("Size", selection: $size) {
                        ForEach(HomeSize.allCases) { Text($0.title).tag($0) }
                    }
                    .segmentedStyle()
                }
            }
            PageEditor(config: config, capacity: layout == .oneAtATime ? "A page holds one module." : "A page holds \(columns == 3 ? "three" : "two") side by side.")
            MusicModuleOptions()
            CalendarModuleOptions()
            BatteriesModuleOptions()
            WeatherModuleOptions()
            RemindersModuleOptions()
            ClockModuleOptions()
            ShortcutsModuleOptions()
        }
    }

    @AppStorage(Prefs.homePages) private var pagesText = ""
    @AppStorage(Prefs.homePage) private var homePage = ""

    /// The home as these settings have it, for the page editor.
    private var config: HomeConfig {
        var order: [HomeModule] = []
        for module in HomeOrder.parse(orderText) + HomeModule.allCases where !order.contains(module) { order.append(module) }
        return HomeConfig(layout: layout, columns: columns, order: order, hidden: Set(HomeOrder.parse(hiddenText)),
                          saved: HomeArrangement.parse(pagesText), size: size, homePage: homePage)
    }
}

/// The open island's pages, each its own group of rows. Drag a module over another and it moves there
/// at once, the rows sliding to make room (onto a full page the two swap); drag a page by its name and
/// drop it where it should go; drop a module on New Page for a page of its own. The shelf is a page too,
/// so it can go first and be one swipe to the left. The house marks the page the island opens on.
private struct PageEditor: View {
    @AppStorage(Prefs.homePages) private var pagesText = ""
    @AppStorage(Prefs.homeHidden) private var hiddenText = ""
    @AppStorage(Prefs.homePage) private var homePage = ""
    let config: HomeConfig
    /// How many modules a page holds, for the footer.
    let capacity: String
    @State private var dragging: Dragged?
    /// Where a dragged page (or a module over New Page) would land, lit until the drop.
    @State private var target: String?
    /// Rows keep their identity from page to page, so a module glides to where it goes.
    @Namespace private var rows

    enum Dragged: Equatable {
        case module(HomeModule)
        case page(Int)
    }

    /// Rows making room as a drag passes, quick and settled, as a list reorders.
    private static let slide = Animation.spring(response: 0.3, dampingFraction: 0.86)

    var body: some View {
        let arrangement = config.arrangement
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(arrangement.pages.enumerated()), id: \.offset) { index, page in
                VStack(alignment: .leading, spacing: 8) {
                    pageTitle(index, page: page)
                    VStack(spacing: 0) {
                        switch page {
                        case .shelf:
                            ShelfRow()
                                .matchedGeometryEffect(id: "shelf", in: rows)
                                .onDrag { start(.page(index)) }
                                .onDrop(of: [.text], delegate: drop("p\(index)") { dragged in
                                    guard case .page(let from) = dragged else { return false }
                                    return change { $0.movePage(from, to: index) }
                                })
                        case .modules(let modules):
                            ForEach(Array(modules.enumerated()), id: \.element) { row, module in
                                if row > 0 { Divider() }
                                moduleRow(module, page: index)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(SettingsTheme.group, in: .rect(cornerRadius: 12))
                    .overlay {
                        if target == "p\(index)", dragging != .page(index) {
                            RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                }
                .padding(.top, 20)
            }
            newPage
            Text("\(capacity) The house marks the home page, where the island opens. A module shows when it has something to show: Music while a track is loaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
                .padding(.top, 8)
        }
        // A drag let go outside the list never reaches a drop; the button coming up ends it.
        .task(id: dragging) {
            while dragging != nil, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    dragging = nil
                    target = nil
                }
            }
        }
    }

    /// "Page 2" with its house, dragged to move the page; a module over it joins the page if there's room.
    private func pageTitle(_ index: Int, page: HomeArrangement.Page) -> some View {
        let isHome = config.homeIndex == index
        return HStack(spacing: 10) {
            Text("Page \(index + 1)").font(.headline)
            Spacer()
            // The house marks where the island opens; click another page's to make it home.
            Button {
                withAnimation(Self.slide) { homePage = HomeArrangement.anchor(of: page) }
            } label: {
                Image(systemName: isHome ? "house.fill" : "house")
                    .foregroundStyle(isHome ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(isHome ? "Home: the island opens here" : "Make this the home page")
            .accessibilityLabel(isHome ? "Home page" : "Make Page \(index + 1) the home page")
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onDrag { start(.page(index)) }
        .onDrop(of: [.text], delegate: drop("p\(index)") { dragged in
            switch dragged {
            case .page(let from): return change { $0.movePage(from, to: index) }
            case .module(let module): return change { $0.move(module, toPage: index, hidden: config.hidden, perPage: config.perPage) }
            }
        })
        .accessibilityAction(named: "Move page up") { _ = change { $0.movePage(index, to: index - 1) } }
        .accessibilityAction(named: "Move page down") { _ = change { $0.movePage(index, to: index + 1) } }
    }

    private func moduleRow(_ module: HomeModule, page: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(module.title)
            Spacer(minLength: 12)
            Toggle(module.title, isOn: Binding(get: { !config.hidden.contains(module) }, set: { on in
                var hidden = config.hidden
                if on { hidden.remove(module) } else { hidden.insert(module) }
                withAnimation(Self.slide) { hiddenText = HomeOrder.string(HomeModule.allCases.filter(hidden.contains)) }
            }))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .opacity(dragging == .module(module) ? 0.35 : 1)
        .matchedGeometryEffect(id: module.rawValue, in: rows)
        .onDrag { start(.module(module)) }
        .onDrop(of: [.text], delegate: drop(module.rawValue) { dragged in
            switch dragged {
            case .module(let other): return other != module && change { $0.move(other, onto: module, hidden: config.hidden, perPage: config.perPage) }
            case .page(let from): return change { $0.movePage(from, to: page) }
            }
        })
    }

    /// Where a module gets a page of its own, or a page goes last.
    private var newPage: some View {
        let lit = target == "new"
        return Text("New Page")
            .foregroundStyle(lit ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(lit ? Color.accentColor : Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: lit ? 2 : 1, dash: lit ? [] : [5, 4]))
            }
            .animation(.easeOut(duration: 0.15), value: lit)
            .padding(.top, 20)
            .onDrop(of: [.text], delegate: drop("new", live: false) { dragged in
                switch dragged {
                case .module(let module): return change { $0.moveToNewPage(module) }
                case .page(let from): return change { $0.movePageToEnd(from) }
                }
            })
    }

    private func start(_ dragged: Dragged) -> NSItemProvider {
        dragging = dragged
        return NSItemProvider(object: "nook-page" as NSString)
    }

    private func drop(_ id: String, live: Bool = true, apply: @escaping (Dragged) -> Bool) -> PageDrop {
        PageDrop(id: id, live: live, target: $target, dragging: $dragging, apply: apply)
    }

    /// Changes the pages as shown, the rows sliding into place, and saves them. Whether anything moved.
    private func change(_ edit: (inout HomeArrangement) -> Void) -> Bool {
        var arrangement = config.arrangement
        let before = arrangement
        edit(&arrangement)
        let saved = arrangement.normalized(hidden: config.hidden, perPage: config.perPage)
        guard saved != before else { return false }
        withAnimation(Self.slide) { pagesText = saved.string }
        return true
    }
}

/// A place in the page editor something can be dropped. A module moves as soon as it's over a row
/// (`live`); a page, or anything over New Page, lights its place and moves on the drop, since a page
/// moving under the pointer would swap straight back.
private struct PageDrop: DropDelegate {
    let id: String
    let live: Bool
    @Binding var target: String?
    @Binding var dragging: PageEditor.Dragged?
    let apply: (PageEditor.Dragged) -> Bool

    private var movesLive: Bool {
        if live, case .module = dragging { true } else { false }
    }

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }

    func dropEntered(info: DropInfo) {
        guard let dragging else { return }
        if movesLive { _ = apply(dragging) } else { target = id }
    }

    func dropExited(info: DropInfo) {
        if target == id { target = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dragging = nil
            target = nil
        }
        guard let dragging else { return false }
        return movesLive || apply(dragging)
    }
}

/// The shelf's page in the editor: it has no modules, only its place among the pages.
private struct ShelfRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Shelf")
                Text("AirDrop and the files you keep").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

private struct MusicModuleOptions: View {
    @AppStorage(Prefs.musicLeftButton) private var left = MusicButton.favorite
    @AppStorage(Prefs.musicRightButton) private var right = MusicButton.output
    @AppStorage(Prefs.musicShowsTotal) private var showsTotal = false

    var body: some View {
        SettingsSection("Music", footer: left == .favorite || right == .favorite ? "Favorite shows only for players that take favorites, like Music." : nil) {
            SettingsRow("Left button") { buttonPicker("Left button", $left, other: right) }
            SettingsRow("Right button") { buttonPicker("Right button", $right, other: left) }
            SettingsRow("Time after the bar", description: "Clicking the time on the player switches it too.") {
                Picker("Time after the bar", selection: $showsTotal) {
                    Text("Time left").tag(false)
                    Text("Length").tag(true)
                }
                .segmentedStyle()
            }
        }
    }

    /// Each side offers everything but what the other side already does.
    private func buttonPicker(_ title: String, _ selection: Binding<MusicButton>, other: MusicButton) -> some View {
        Picker(title, selection: selection) {
            ForEach(MusicButton.allCases.filter { $0 == .none || $0 != other || $0 == selection.wrappedValue }) {
                Text($0.title).tag($0)
            }
        }
        .menuStyle()
    }
}

private struct CalendarModuleOptions: View {
    @AppStorage(Prefs.calendarWeekStart) private var weekStart = WeekStart.system
    @AppStorage(Prefs.calendarDots) private var dots = false
    @AppStorage(Prefs.calendarDimWeekends) private var dimWeekends = true

    var body: some View {
        SettingsSection("Calendar") {
            SettingsRow("Week starts on") {
                Picker("Week starts on", selection: $weekStart) {
                    ForEach(WeekStart.allCases) { Text($0.title).tag($0) }
                }
                .menuStyle()
            }
            SettingsToggle("Mark days with events", isOn: $dots)
            SettingsToggle("Weekends in gray", isOn: $dimWeekends)
        }
    }
}

private struct BatteriesModuleOptions: View {
    @AppStorage(Prefs.batteriesIncludeMac) private var includeMac = true

    var body: some View {
        SettingsSection("Batteries", footer: "AirPods and their case, Magic Keyboard, Mouse and Trackpad, and other Bluetooth devices that report a level. iPhone and Apple Watch don't share theirs with apps.") {
            SettingsToggle("Include this Mac", isOn: $includeMac)
        }
    }
}

private struct WeatherModuleOptions: View {
    @AppStorage(Prefs.weatherCurrentLocation) private var currentLocation = true
    @AppStorage(Prefs.weatherPlaces) private var places = ""
    @AppStorage(Prefs.weatherUnit) private var unit = TemperatureUnit.auto

    var body: some View {
        SettingsSection("Weather", footer: "One place at a time; click its name on the island for the next. Forecasts from Open-Meteo.") {
            SettingsRow("Temperature", description: unit == .auto ? "As this Mac is set in Language & Region." : nil) {
                Picker("Temperature", selection: $unit) {
                    ForEach(TemperatureUnit.allCases) { Text($0.title).tag($0) }
                }
                .segmentedStyle()
            }
            SettingsToggle("My Location", description: "The weather where this Mac is.", isOn: $currentLocation)
            PlaceList(json: $places, limit: 8)
        }
    }
}

private struct RemindersModuleOptions: View {
    @AppStorage(Prefs.remindersList) private var list = ""

    var body: some View {
        let lists = RemindersModel.allLists()
        SettingsSection("Reminders", footer: lists.isEmpty ? "Click Show Reminders on the island to let Nook read your lists." : nil) {
            SettingsRow("List") {
                Picker("List", selection: $list) {
                    Text("Default List").tag("")
                    if !lists.isEmpty { Divider() }
                    ForEach(lists, id: \.id) { Text($0.title).tag($0.id) }
                }
                .menuStyle()
                .disabled(lists.isEmpty)
            }
        }
    }
}

private struct ClockModuleOptions: View {
    @AppStorage(Prefs.clockPlaces) private var places = ""
    @AppStorage(Prefs.clockStyle) private var style = ClockStyle.analog

    var body: some View {
        // Each city's time, kept current while Settings is open.
        TimelineView(.everyMinute) { context in
            SettingsSection("World Clock", footer: "Up to four cities, as the World Clock widget shows.") {
                SettingsRow("Style") {
                    Picker("Style", selection: $style) {
                        ForEach(ClockStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .segmentedStyle()
                }
                PlaceList(json: $places,
                          defaults: ClockCity.defaults.map { Place(name: $0.name, latitude: 0, longitude: 0, timeZoneID: $0.timeZone.identifier) },
                          limit: 4) { place in
                    context.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: place.timeZone))
                }
            }
        }
    }
}

private struct ShortcutsModuleOptions: View {
    @AppStorage(Prefs.shortcutsPicked) private var pickedText = ""
    /// Every shortcut, read when the section shows; nil until then or if Shortcuts can't be read.
    @State private var all: [String]?

    var body: some View {
        let picked = ShortcutsModel.picks(from: pickedText)
        let rest = (all ?? []).filter { !picked.contains($0) }
        SettingsSection("Shortcuts", footer: "Up to four, in this order. With none picked, the island shows your first four.") {
            ForEach(picked, id: \.self) { name in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                        if let all, !all.contains(name) {
                            Text("Not in Shortcuts").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 12)
                    Button { pickedText = ShortcutsModel.json(picked.filter { $0 != name }) } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(name)")
                    .accessibilityLabel("Remove \(name)")
                }
                .padding(.vertical, 9)
            }
            HStack {
                Menu("Add Shortcut…") {
                    ForEach(rest, id: \.self) { name in
                        Button(name) { pickedText = ShortcutsModel.json(picked + [name]) }
                    }
                }
                .fixedSize()
                .disabled(picked.count >= 4 || rest.isEmpty)
                Spacer()
            }
            .padding(.vertical, 9)
        }
        .task { all = await ShortcutsModel.list() }
    }
}

/// Side by side or one at a time, as small drawings of the open island.
private struct HomeLayoutPicker: View {
    @Binding var selection: HomeLayout

    var body: some View {
        HStack(spacing: 16) {
            ForEach(HomeLayout.allCases) { layout in
                let selected = selection == layout
                Button { selection = layout } label: {
                    VStack(spacing: 6) {
                        HomeLayoutThumbnail(layout: layout)
                            .frame(width: 200, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 1)
                            )
                        Text(layout.title)
                            .font(.callout)
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// The open island drawn small: a wide island holding two modules, or a narrow one holding one with
/// page dots.
private struct HomeLayoutThumbnail: View {
    let layout: HomeLayout

    var body: some View {
        let wide = layout == .sideBySide
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.27, green: 0.35, blue: 0.49), Color(red: 0.62, green: 0.69, blue: 0.81)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: 8) {
                    MusicSketch()
                    if wide { CalendarSketch() }
                }
                .padding(.horizontal, 9)
                .padding(.top, 13)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(spacing: 2.5) {
                    ForEach(0..<(wide ? 2 : 3), id: \.self) { i in
                        Circle().fill(.white.opacity(i == 0 ? 0.9 : 0.3)).frame(width: 2.5, height: 2.5)
                    }
                }
                .padding(.top, 5)
                .padding(.trailing, 9)
            }
            .frame(width: wide ? 168 : 86, height: 58)
            .background(NotchShape(topRadius: 4, bottomRadius: 13).fill(.black))
        }
        .accessibilityHidden(true)
    }
}

private struct MusicSketch: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.35, green: 0.55, blue: 0.75)).frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Capsule().fill(.white.opacity(0.85)).frame(width: 30, height: 3)
                    Capsule().fill(.white.opacity(0.4)).frame(width: 20, height: 3)
                }
            }
            Capsule().fill(.white.opacity(0.3)).frame(width: 68, height: 2.5)
                .overlay(alignment: .leading) { Capsule().fill(.white.opacity(0.7)).frame(width: 22, height: 2.5) }
            HStack(spacing: 9) {
                ForEach(0..<5, id: \.self) { i in
                    Circle().fill(.white.opacity(i == 2 ? 0.9 : 0.6)).frame(width: i == 2 ? 5 : 4)
                }
            }
        }
        .frame(width: 68, alignment: .leading)
    }
}

private struct CalendarSketch: View {
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(.red).frame(width: 14, height: 2.5)
                Text("29").font(.system(size: 11, weight: .light)).foregroundStyle(.white)
                RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.35)).frame(width: 26, height: 7)
            }
            VStack(alignment: .leading, spacing: 2.5) {
                Capsule().fill(.red).frame(width: 14, height: 2.5)
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 2.5) {
                        ForEach(0..<7, id: \.self) { col in
                            Circle().fill(row == 3 && col == 3 ? Color.red : .white.opacity(col > 4 ? 0.35 : 0.7)).frame(width: 2.5, height: 2.5)
                        }
                    }
                }
            }
        }
    }
}

