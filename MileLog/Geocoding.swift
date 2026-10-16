import CoreLocation
import MapKit

/// Address lookups, in one place.
///
/// Uses the MapKit geocoding requests introduced in iOS 26, which replace
/// the deprecated `CLGeocoder`. Every lookup in the app goes through here, so
/// a future API change touches this file only.
enum Geocoding {

    /// Short human-readable address for a coordinate — street and town,
    /// e.g. "Lendavska ulica 5, Murska Sobota". Empty when nothing is found
    /// or the lookup fails; callers treat the address as best-effort.
    static func shortAddress(for location: CLLocation) async -> String {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first
        else { return "" }
        if let short = item.address?.shortAddress, !short.isEmpty {
            return short
        }
        return item.addressRepresentations?.cityName ?? item.name ?? ""
    }

    /// Coordinate for a typed address (Settings → Home / Work), or nil when
    /// it cannot be resolved.
    static func coordinate(for address: String) async -> CLLocationCoordinate2D? {
        guard let request = MKGeocodingRequest(addressString: address),
              let item = try? await request.mapItems.first
        else { return nil }
        return item.location.coordinate
    }
}
