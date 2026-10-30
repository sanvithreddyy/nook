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
            SettingsSection("Modules", footer: "Drag to reorder. A module shows when it has something to show: Music while a track is loaded.") {
                ModuleList(order: order, hidden: hidden) { newOrder in
                    orderText = HomeOrder.string(newOrder)
                } toggle: { module, on in
                    var set = hidden
                    if on { set.remove(module) } else { set.insert(module) }
                    hiddenText = HomeOrder.string(HomeModule.allCases.filter(set.contains))
                }
            }
            MusicModuleOptions()
            CalendarModuleOptions()
            BatteriesModuleOptions()
        }
    }

    private var order: [HomeModule] {
        var order: [HomeModule] = []
        for module in HomeOrder.parse(orderText) + HomeModule.allCases where !order.contains(module) { order.append(module) }
        return order
    }

    private var hidden: Set<HomeModule> { Set(HomeOrder.parse(hiddenText)) }
}

/// Rows you drag to reorder, each with its switch. Plain settings rows rather than a List, so they line
/// up with every other row; a row moves into place as the drag passes over its neighbours.
private struct ModuleList: View {
    let order: [HomeModule]
    let hidden: Set<HomeModule>
    let move: ([HomeModule]) -> Void
    let toggle: (HomeModule, Bool) -> Void
    @State private var dragging: HomeModule?

    var body: some View {
        ForEach(order) { module in
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(module.title)
                Spacer(minLength: 12)
                Toggle(module.title, isOn: Binding(get: { !hidden.contains(module) }, set: { toggle(module, $0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .onDrag {
                dragging = module
                return NSItemProvider(object: module.rawValue as NSString)
            }
            .onDrop(of: [.text], delegate: ReorderDrop(target: module, order: order, dragging: $dragging, move: move))
            .accessibilityAction(named: "Move up") { shift(module, by: -1) }
            .accessibilityAction(named: "Move down") { shift(module, by: 1) }
        }
    }

    private func shift(_ module: HomeModule, by step: Int) {
        guard let index = order.firstIndex(of: module), order.indices.contains(index + step) else { return }
        var next = order
        next.swapAt(index, index + step)
        move(next)
    }
}

private struct ReorderDrop: DropDelegate {
    let target: HomeModule
    let order: [HomeModule]
    @Binding var dragging: HomeModule?
    let move: ([HomeModule]) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = order.firstIndex(of: dragging), let to = order.firstIndex(of: target) else { return }
        var next = order
        next.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        withAnimation(.easeOut(duration: 0.15)) { move(next) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

private struct MusicModuleOptions: View {
    @AppStorage(Prefs.musicLeftButton) private var left = MusicButton.favorite
    @AppStorage(Prefs.musicRightButton) private var right = MusicButton.output
    @AppStorage(Prefs.musicShowsTotal) private var showsTotal = false

    var body: some View {
        SettingsSection("Music", footer: left == .favorite || right == .favorite ? "Favorite shows only for players that take favorites, like Music." : nil) {
            SettingsRow("Left button") { buttonPicker("Left button", $left) }
            SettingsRow("Right button") { buttonPicker("Right button", $right) }
            SettingsRow("Time after the bar", description: "Clicking the time on the player switches it too.") {
                Picker("Time after the bar", selection: $showsTotal) {
                    Text("Time left").tag(false)
                    Text("Length").tag(true)
                }
                .segmentedStyle()
            }
        }
    }

    private func buttonPicker(_ title: String, _ selection: Binding<MusicButton>) -> some View {
        Picker(title, selection: selection) {
            ForEach(MusicButton.allCases) { Text($0.title).tag($0) }
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

