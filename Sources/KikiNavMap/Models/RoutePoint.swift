import Foundation

public enum RoutePointKind: Sendable, Hashable, Codable {
    case airport(String)     // 4-letter ICAO, e.g. "EFHK"
    case waypoint(String)    // 5-letter fix, e.g. "DIVKO"
    case coordinate(String)  // e.g. "60N120W"
}

public struct RoutePoint: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var ident: String
    public var latitude: Double
    public var longitude: Double
    public var kind: RoutePointKind

    public init(id: UUID = UUID(), ident: String, latitude: Double, longitude: Double, kind: RoutePointKind) {
        self.id = id
        self.ident = ident.uppercased()
        self.latitude = latitude
        self.longitude = longitude
        self.kind = kind
    }

    public var isCoordinate: Bool {
        if case .coordinate = kind { return true }
        return false
    }

    public var isAirport: Bool {
        if case .airport = kind { return true }
        return false
    }
}
