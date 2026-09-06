import Foundation

public struct AirportMetaEntry: Codable, Sendable {
    public let i: String // IATA code
    public let n: String // English Name
    public let c: String // Municipality / City
}

public final class AirportMetadata: Sendable {
    public static let shared = AirportMetadata()

    public let database: [String: AirportMetaEntry]

    private init() {
        var loaded: [String: AirportMetaEntry] = [:]

        // Search in common bundle and filesystem paths
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: "airports_meta", withExtension: "json"),
            Bundle.main.resourceURL?.appendingPathComponent("airports_meta.json"),
            Bundle.main.resourceURL?.appendingPathComponent("Resources/airports_meta.json"),
            URL(fileURLWithPath: "Sources/KikiNavMap/Resources/airports_meta.json"),
            URL(fileURLWithPath: "../Sources/KikiNavMap/Resources/airports_meta.json"),
            URL(fileURLWithPath: "../../Sources/KikiNavMap/Resources/airports_meta.json")
        ]

        for case let url? in candidateURLs {
            if FileManager.default.fileExists(atPath: url.path),
               let data = try? Data(contentsOf: url),
               let dict = try? JSONDecoder().decode([String: AirportMetaEntry].self, from: data) {
                loaded = dict
                break
            }
        }

        self.database = loaded
    }

    public func lookup(_ icao: String) -> AirportMetaEntry? {
        database[icao.uppercased()]
    }
}

