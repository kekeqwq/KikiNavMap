import Foundation

public struct Waypoint: Identifiable, Sendable, Hashable, Codable {
    public let id: String              // 5-letter ICAO fix, e.g. "DIVKO"
    public let latitude: Double
    public let longitude: Double

    public init(id: String, latitude: Double, longitude: Double) {
        self.id = id.uppercased()
        self.latitude = latitude
        self.longitude = longitude
    }

    public static func isValidFiveLetterIdent(_ s: String) -> Bool {
        guard s.count == 5 else { return false }
        return s.allSatisfy { $0 >= "A" && $0 <= "Z" }
    }

    /// Validates if an ident is an aviation navigational fix, VOR, or NDB (1 to 5 alphanumeric characters)
    public static func isValidNavIdent(_ s: String) -> Bool {
        guard s.count >= 1 && s.count <= 5 else { return false }
        return s.allSatisfy { ($0 >= "A" && $0 <= "Z") || ($0 >= "0" && $0 <= "9") }
    }
}
