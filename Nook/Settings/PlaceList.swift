import MapKit
import SwiftUI

/// Cities in a Settings section, as Clock and Weather list theirs: each on its row with a remove
/// button, then Add City…, which searches Apple's maps as you type. Kept as Place JSON under one key.
struct PlaceList: View {
    @Binding var json: String
    /// What an untouched list shows: the World Clock's cities before any are picked.
    var defaults: [Place] = []
    let limit: Int
    /// A second line on a city's row, like Clock's time there.
    var detail: (Place) -> String? = { _ in nil }
    @State private var adding = false

    private var places: [Place] { json.isEmpty ? defaults : Place.list(from: json) }

    var body: some View {
        ForEach(places) { place in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name)
                    if let detail = detail(place) {
                        Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer(minLength: 12)
                Button { save(places.filter { $0 != place }) } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove \(place.name)")
                .accessibilityLabel("Remove \(place.name)")
            }
            .padding(.vertical, 9)
        }
        HStack {
            Button("Add City…") { adding = true }
                .disabled(places.count >= limit)
                .popover(isPresented: $adding, arrowEdge: .bottom) {
                    CityPicker { place in
                        if !places.contains(place) { save(places + [place]) }
                        adding = false
                    }
                }
            Spacer()
        }
        .padding(.vertical, 9)
    }

    private func save(_ places: [Place]) {
        json = Place.json(places)
    }
}

/// The search behind Add City…: a field, and the cities that match under it.
private struct CityPicker: View {
    let pick: (Place) -> Void
    @State private var search = PlaceSearch()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $search.query, prompt: Text("Search for a city"))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .padding(10)
            Divider()
            List(search.results, id: \.self) { result in
                Button {
                    Task { if let place = await search.place(for: result) { pick(place) } }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.title)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .frame(width: 300, height: 260)
        .onAppear { focused = true }
    }
}
