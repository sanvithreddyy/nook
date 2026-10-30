import AppKit
import Combine
import EventKit
import SwiftUI

struct CalendarPane: View {
    @AppStorage(Prefs.calendar) private var enabled = true
    @AppStorage(Prefs.calendarLeadMinutes) private var lead = 10
    @AppStorage(Prefs.calendarStayMinutes) private var stay = 5
    @AppStorage(Prefs.calendarHideAllDay) private var hideAllDay = false
    @AppStorage(Prefs.calendarPeekAtStart) private var peekAtStart = true
    @AppStorage(Prefs.calendarChime) private var chime = ""
    @AppStorage(Prefs.calendarHidden) private var hiddenText = ""
    @State private var status = EKEventStore.authorizationStatus(for: .event)
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPage(title: "Calendar", area: Prefs.calendarArea, preview: "Opens the calendar on the notch while you change things here.") {
            SettingsSection {
                SettingsToggle("Show upcoming events", isOn: $enabled)
                SettingsRow("Show a meeting in the notch") {
                    Picker("Show a meeting in the notch", selection: $lead) {
                        ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) minutes before").tag($0) }
                    }
                    .menuStyle()
                }
                .disabled(!enabled)
                SettingsRow("Once it starts") {
                    Picker("Once it starts", selection: $stay) {
                        Text("Leave the notch").tag(0)
                        Text("Stay 5 minutes").tag(5)
                        Text("Stay until it ends").tag(-1)
                    }
                    .menuStyle()
                }
                .disabled(!enabled)
            }
            if enabled {
                SettingsSection("Access") {
                    SettingsRow("Calendar access", description: status == .fullAccess ? nil : "Nook reads your events to show what's next. Nothing leaves your Mac.") {
                        switch status {
                        case .fullAccess:
                            Text("Allowed").foregroundStyle(.secondary)
                        case .notDetermined:
                            Button("Allow…") {
                                Task { _ = try? await EKEventStore().requestFullAccessToEvents() }
                            }
                        default:
                            Button("Open Privacy Settings…") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                            }
                        }
                    }
                }
            }
            SettingsSection("When an event starts") {
                SettingsToggle("Show its title under the island", isOn: $peekAtStart)
                SettingsRow("Sound") {
                    Picker("Sound", selection: $chime) {
                        Text("None").tag("")
                        Divider()
                        ForEach(TimerPane.sounds, id: \.self) { Text($0).tag($0) }
                    }
                    .menuStyle()
                    .onChange(of: chime) { _, new in
                        if !new.isEmpty { NSSound(named: new)?.play() }
                    }
                }
            }
            .disabled(!enabled)
            SettingsSection("Events") {
                SettingsToggle("Hide all-day events", isOn: $hideAllDay)
            }
            .disabled(!enabled)
            if enabled, status == .fullAccess {
                let calendars = CalendarModel.allCalendars()
                SettingsSection("Calendars") {
                    ForEach(calendars, id: \.id) { calendar in
                        CalendarSwitch(title: calendar.title, account: calendar.account, color: calendar.color, isOn: showing(calendar.id))
                    }
                }
            }
        }
        .onReceive(poll) { _ in status = EKEventStore.authorizationStatus(for: .event) }
    }

    /// On while the calendar's events show; reads the hidden list so the switch updates with it.
    private func showing(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !hiddenText.split(separator: ",").contains(Substring(id)) },
            set: { show in
                var hidden = Set(hiddenText.split(separator: ",").map(String.init))
                if show { hidden.remove(id) } else { hidden.insert(id) }
                hiddenText = hidden.sorted().joined(separator: ",")
            }
        )
    }
}

/// A calendar's row: its colour, its name and account, and a switch.
private struct CalendarSwitch: View {
    let title: String
    let account: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(account).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }
        .padding(.vertical, 8)
    }
}
