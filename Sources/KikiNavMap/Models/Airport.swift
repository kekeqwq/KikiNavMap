import Foundation

public struct Airport: Identifiable, Sendable, Hashable, Codable {
    public let id: String              // 4-letter ICAO code, e.g. "EFHK"
    public let iata: String            // 3-letter IATA code, e.g. "HEL"
    public let name: String            // Airport name, e.g. "Helsinki Vantaa"
    public let city: String            // City / Municipality, e.g. "Helsinki"
    public let latitude: Double
    public let longitude: Double
    public let elevationMeters: Double

    public init(
        id: String,
        iata: String = "",
        name: String,
        city: String = "",
        latitude: Double,
        longitude: Double,
        elevationMeters: Double = 0.0
    ) {
        self.id = id.uppercased()
        self.iata = iata.uppercased()
        self.name = name
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.elevationMeters = elevationMeters
    }

    public var displayText: String {
        var parts: [String] = [id]
        if !iata.isEmpty {
            parts.append("(\(iata))")
        }
        if !name.isEmpty {
            parts.append("- \(name)")
        }
        return parts.joined(separator: " ")
    }
}
