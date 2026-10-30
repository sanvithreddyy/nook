import AppKit
import Combine
import EventKit
import SwiftUI

struct CalendarPane: View {
    @AppStorage(Prefs.calendar) private var enabled = true
    @AppStorage(Prefs.calendarLeadMinutes) private var lead = 10
    @State private var status = EKEventStore.authorizationStatus(for: .event)
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPage(title: "Calendar") {
            SettingsSection {
                SettingsToggle("Show upcoming events", isOn: $enabled)
                SettingsRow("Show a meeting in the notch") {
                    Picker("Show a meeting in the notch", selection: $lead) {
                        ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) minutes before").tag($0) }
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
        }
        .onReceive(poll) { _ in status = EKEventStore.authorizationStatus(for: .event) }
    }
}
