import Foundation
import Combine

@MainActor
public final class NavDataManager: ObservableObject {
    public static let shared = NavDataManager()

    @Published public private(set) var airports: [Airport] = []
    @Published public private(set) var airportMap: [String: Airport] = [:]
    @Published public private(set) var waypoints5: [Waypoint] = []
    @Published public private(set) var airacCycle: String = ""
    @Published public private(set) var isLoaded: Bool = false
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var statusMessage: String = "No navigation data loaded"

    public private(set) var kdTree: SpatialKDTree = SpatialKDTree()

    private let fileManager = FileManager.default
    private let reader = BGLReader()

    public var cacheDirectory: URL {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let base = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("KikiNavMap", isDirectory: true)
    }

    public var navDataCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("NavData", isDirectory: true)
    }

    private var airportsCacheURL: URL {
        navDataCacheDirectory.appendingPathComponent("airports.json")
    }

    private var waypointsCacheURL: URL {
        navDataCacheDirectory.appendingPathComponent("waypoints5.json")
    }

    private var cycleCacheURL: URL {
        navDataCacheDirectory.appendingPathComponent("cycle.txt")
    }

    public init() {
        createCacheDirectoriesIfNeeded()
    }

    public func createCacheDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: navDataCacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Initial Load
    public func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = "Checking cached navigation data..."

        // 1. Try reading from cache
        if loadFromCache() {
            isLoading = false
            return
        }

        // 2. Auto-scan local data/2606 if present
        let local2606URL = URL(fileURLWithPath: "data/2606")
        if fileManager.fileExists(atPath: local2606URL.path) {
            statusMessage = "Discovered AIRAC 2606 dataset, parsing..."
            await scanAndCache(from: local2606URL)
        } else {
            statusMessage = "Ready. Please import AIRAC data in Settings."
        }

        isLoading = false
    }

    // MARK: - Cache Load & Save
    private func loadFromCache() -> Bool {
        var loadedApt = false
        var loadedWpt = false

        if fileManager.fileExists(atPath: airportsCacheURL.path),
           let data = try? Data(contentsOf: airportsCacheURL),
           let list = try? JSONDecoder().decode([Airport].self, from: data) {
            // Enrich with metadata in case cached airports had TT: names or missing IATA
            let enriched = list.map { apt -> Airport in
                let meta = AirportMetadata.shared.lookup(apt.id)
                let iata = apt.iata.isEmpty ? (meta?.i ?? "") : apt.iata
                let city = apt.city.isEmpty ? (meta?.c ?? "") : apt.city
                var cleanName = apt.name
                if cleanName.isEmpty || cleanName.hasPrefix("TT:") {
                    cleanName = meta?.n.isEmpty == false ? meta!.n : apt.id
                }
                return Airport(
                    id: apt.id,
                    iata: iata,
                    name: cleanName,
                    city: city,
                    latitude: apt.latitude,
                    longitude: apt.longitude,
                    elevationMeters: apt.elevationMeters
                )
            }
            self.airports = enriched
            self.airportMap = Dictionary(uniqueKeysWithValues: enriched.map { ($0.id, $0) })
            loadedApt = true
        }

        if fileManager.fileExists(atPath: waypointsCacheURL.path),
           let data = try? Data(contentsOf: waypointsCacheURL),
           let list = try? JSONDecoder().decode([Waypoint].self, from: data) {
            // Filter strictly valid 5-letter alphabetic fixes
            let valid = list.filter { Waypoint.isValidFiveLetterIdent($0.id) }
            self.waypoints5 = valid
            self.kdTree.build(waypoints: valid)
            loadedWpt = true
        }

        if fileManager.fileExists(atPath: cycleCacheURL.path),
           let str = try? String(contentsOf: cycleCacheURL, encoding: .utf8) {
            self.airacCycle = str.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if loadedApt || loadedWpt {
            self.isLoaded = true
            let prefix = airacCycle.isEmpty ? "AIRAC Active" : "AIRAC \(airacCycle) Active"
            self.statusMessage = "\(prefix): \(airports.count) airports, \(waypoints5.count) 5-letter fixes"
            return true
        }
        return false
    }

    private func saveAirportsToCache() {
        createCacheDirectoriesIfNeeded()
        if let data = try? JSONEncoder().encode(airports) {
            try? data.write(to: airportsCacheURL, options: .atomic)
        }
    }

    private func saveWaypointsToCache() {
        createCacheDirectoriesIfNeeded()
        if let data = try? JSONEncoder().encode(waypoints5) {
            try? data.write(to: waypointsCacheURL, options: .atomic)
        }
    }

    private func saveCycleToCache(_ cycle: String) {
        createCacheDirectoriesIfNeeded()
        try? cycle.write(to: cycleCacheURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Cycle Detection
    public func detectCycle(in rootURL: URL) -> String? {
        if let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent.lowercased() == "cycle.json",
                   let data = try? Data(contentsOf: fileURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let cycle = json["Cycle"] as? String {
                    return cycle
                }
            }
        }
        let name = rootURL.lastPathComponent
        if name.count == 4 && name.allSatisfy({ $0.isNumber }) {
            return name
        }
        return nil
    }

    // MARK: - Scanning
    public func scanAndCache(from url: URL) async {
        isLoading = true
        let reader = self.reader

        if let detected = detectCycle(in: url) {
            self.airacCycle = detected
            saveCycleToCache(detected)
        }

        // Run heavy BGL parsing off the main actor
        let parsed = await Task.detached(priority: .userInitiated) {
            return reader.scanDirectory(at: url, parseAirports: true, parseWaypoints: true)
        }.value

        self.airports = parsed.airports
        self.airportMap = Dictionary(uniqueKeysWithValues: parsed.airports.map { ($0.id, $0) })
        self.waypoints5 = parsed.waypoints
        self.kdTree.build(waypoints: parsed.waypoints)

        saveAirportsToCache()
        saveWaypointsToCache()

        self.isLoaded = true
        let prefix = airacCycle.isEmpty ? "AIRAC Active" : "AIRAC \(airacCycle) Active"
        self.statusMessage = "\(prefix): \(airports.count) airports, \(waypoints5.count) 5-letter fixes"
        self.isLoading = false
    }

    // MARK: - Separate Import
    public func importAirports(from url: URL) async {
        isLoading = true
        statusMessage = "Scanning airports in \(url.lastPathComponent)..."
        let reader = self.reader

        let parsed = await Task.detached(priority: .userInitiated) {
            return reader.scanDirectory(at: url, parseAirports: true, parseWaypoints: false)
        }.value

        self.airports = parsed.airports
        self.airportMap = Dictionary(uniqueKeysWithValues: parsed.airports.map { ($0.id, $0) })
        saveAirportsToCache()

        self.isLoaded = true
        self.statusMessage = "Airports updated: \(airports.count) airports loaded"
        self.isLoading = false
    }

    public func importWaypoints(from url: URL) async {
        isLoading = true
        statusMessage = "Scanning 5-letter fixes in \(url.lastPathComponent)..."
        let reader = self.reader

        let parsed = await Task.detached(priority: .userInitiated) {
            return reader.scanDirectory(at: url, parseAirports: false, parseWaypoints: true)
        }.value

        self.waypoints5 = parsed.waypoints
        self.kdTree.build(waypoints: parsed.waypoints)
        saveWaypointsToCache()

        self.isLoaded = true
        self.statusMessage = "Waypoints updated: \(waypoints5.count) 5-letter fixes loaded"
        self.isLoading = false
    }

    // MARK: - Clear All Cache
    public func clearAllCache() {
        try? fileManager.removeItem(at: navDataCacheDirectory)
        createCacheDirectoriesIfNeeded()

        self.airports = []
        self.airportMap = [:]
        self.waypoints5 = []
        self.airacCycle = ""
        self.kdTree = SpatialKDTree()
        self.isLoaded = false
        self.statusMessage = "Cache cleared. Ready for new import."
    }

    // MARK: - Search
    public func searchAirports(query: String) -> [Airport] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !q.isEmpty else { return [] }

        var exactIcao: [Airport] = []
        var exactIata: [Airport] = []
        var prefixIcao: [Airport] = []
        var prefixIata: [Airport] = []
        var cityMatches: [Airport] = []
        var nameMatches: [Airport] = []

        for a in airports {
            let aIcao = a.id
            let aIata = a.iata.uppercased()
            let aName = a.name.uppercased()
            let aCity = a.city.uppercased()

            if aIcao == q {
                exactIcao.append(a)
            } else if !aIata.isEmpty && aIata == q {
                exactIata.append(a)
            } else if aIcao.hasPrefix(q) {
                prefixIcao.append(a)
            } else if !aIata.isEmpty && aIata.hasPrefix(q) {
                prefixIata.append(a)
            } else if !aCity.isEmpty && aCity.contains(q) {
                cityMatches.append(a)
            } else if !aName.isEmpty && aName.contains(q) {
                nameMatches.append(a)
            }
        }

        var results: [Airport] = []
        for bucket in [exactIcao, exactIata, prefixIcao, prefixIata, cityMatches, nameMatches] {
            for a in bucket {
                if !results.contains(where: { $0.id == a.id }) {
                    results.append(a)
                    if results.count >= 12 { return results }
                }
            }
        }

        return results
    }
}
