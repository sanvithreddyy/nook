import Foundation
import MapKit

/// A city picked in Settings, for the World Clock and Weather: the name to show, where it is, and its
/// time zone. Lists of them are kept in the defaults as JSON.
nonisolated struct Place: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZoneID: String

    var id: String { "\(name)@\(latitude),\(longitude)" }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    static func list(from json: String) -> [Place] {
        (try? JSONDecoder().decode([Place].self, from: Data(json.utf8))) ?? []
    }

    static func json(_ places: [Place]) -> String {
        (try? JSONEncoder().encode(places)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}

/// Finds cities the way Clock and Weather do: type a few letters, pick one from the list. Apple's own
/// map search, so it needs no account and knows each city's time zone.
@Observable
final class PlaceSearch: NSObject {
    var query = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var results: [MKLocalSearchCompletion] = []

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(including: .locality)
    }

    /// The city a result names, with its coordinates and time zone; nil if the map can't place it.
    func place(for completion: MKLocalSearchCompletion) async -> Place? {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first,
              let timeZone = item.timeZone
        else { return nil }
        let coordinate = item.placemark.coordinate
        return Place(name: item.placemark.locality ?? completion.title, latitude: coordinate.latitude,
                     longitude: coordinate.longitude, timeZoneID: timeZone.identifier)
    }
}

extension PlaceSearch: @preconcurrency MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        results = []
    }
}
