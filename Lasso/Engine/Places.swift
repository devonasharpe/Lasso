import Foundation
import AVFoundation
import ImageIO
import CoreLocation

/// A GPS position read from a photo or video.
struct GPS: Hashable {
    let lat: Double
    let lon: Double
    /// Rounded to about 1 km, so nearby files share one place lookup.
    var key: String { String(format: "%.2f,%.2f", lat, lon) }
    var isValid: Bool { !(lat == 0 && lon == 0) && abs(lat) <= 90 && abs(lon) <= 180 }
}

/// Reads where a file was taken and turns it into a place name for the file name.
enum Places {
    static func photoGPS(_ url: URL) -> GPS? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let g = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let lat = (g[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              let lon = (g[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue else { return nil }
        let latRef = g[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
        let lonRef = g[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
        let gps = GPS(lat: latRef == "S" ? -lat : lat, lon: lonRef == "W" ? -lon : lon)
        return gps.isValid ? gps : nil
    }

    static func videoGPS(_ url: URL) async -> GPS? {
        let asset = AVURLAsset(url: url)
        var items: [AVMetadataItem] = []
        if let common = try? await asset.load(.commonMetadata) { items += common }
        if let formats = try? await asset.load(.availableMetadataFormats) {
            for f in formats {
                if let more = try? await asset.loadMetadata(for: f) { items += more }
            }
        }
        for item in items {
            let id = item.identifier?.rawValue ?? ""
            let isLocation = item.commonKey == .commonKeyLocation || id.contains("ISO6709")
                || id.contains("%A9xyz") || id.contains("©xyz") || id.lowercased().contains("location")
            guard isLocation, let s = try? await item.load(.stringValue), let g = parseISO6709(s) else { continue }
            return g
        }
        return nil
    }

    /// "+48.8373+002.3011/" → 48.8373, 2.3011
    static func parseISO6709(_ s: String) -> GPS? {
        let re = try! NSRegularExpression(pattern: "([+-]\\d+(?:\\.\\d+)?)([+-]\\d+(?:\\.\\d+)?)")
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let a = Range(m.range(at: 1), in: s), let b = Range(m.range(at: 2), in: s),
              let lat = Double(s[a]), let lon = Double(s[b]) else { return nil }
        let g = GPS(lat: lat, lon: lon)
        return g.isValid ? g : nil
    }
}

/// Turns a GPS position into a city name, e.g. "LosAngeles" or "Paris".
/// Uses Apple's place lookup (needs an internet connection). Results are remembered.
actor PlaceNamer {
    static let shared = PlaceNamer()
    private var cache: [String: String] = [:]
    private let geocoder = CLGeocoder()

    func name(for g: GPS) async -> String? {
        if let hit = cache[g.key] { return hit }
        let location = CLLocation(latitude: g.lat, longitude: g.lon)
        guard let p = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        guard let raw = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? p.country else { return nil }
        let plain = raw.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        let clean = Wrangler.cleanToken(plain, fallback: "")
        guard !clean.isEmpty else { return nil }
        cache[g.key] = clean
        return clean
    }
}
