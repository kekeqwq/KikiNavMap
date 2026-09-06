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
}
