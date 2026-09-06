import Foundation
import CoreLocation

// Direct test assertions
func assertTrue(_ condition: Bool, _ message: String = "") {
    if !condition {
        print("FAIL: \(message)")
        exit(1)
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "") {
    if a != b {
        print("FAIL: '\(a)' != '\(b)' - \(message)")
        exit(1)
    }
}

@main
struct KikiNavMapTests {
    @MainActor
    static func main() {
        print("--- Starting KikiNavMap Unit Tests ---")
        testCoordinateFix()
        testWaypointValidation()
        testAirportMetadataAndSearch()
        testOptimalRouteOrdering()
        testSpatialKDTree()
        testSnappingEngine()
        testBGLReaderBasics()
        print("--- All Unit Tests PASSED Successfully! ---")
    }

    static func testCoordinateFix() {
        print("Testing CoordinateFix...")
        let code1 = CoordinateFix.format(latitude: 60.12, longitude: -120.45)
        assertEqual(code1, "60N120W", "60N120W formatting")

        let code2 = CoordinateFix.format(latitude: 58.2, longitude: 24.8)
        assertEqual(code2, "58N025E", "58N025E formatting")

        let code3 = CoordinateFix.format(latitude: -22.5, longitude: 119.8)
        assertEqual(code3, "23S120E", "23S120E formatting")

        let parsed1 = CoordinateFix.parse("60N120W")
        assertTrue(parsed1 != nil, "Parse 60N120W")
        assertEqual(parsed1!.0, 60.0, "Lat 60")
        assertEqual(parsed1!.1, -120.0, "Lon -120")

        let parsed2 = CoordinateFix.parse("58N025E")
        assertTrue(parsed2 != nil, "Parse 58N025E")
        assertEqual(parsed2!.0, 58.0, "Lat 58")
        assertEqual(parsed2!.1, 25.0, "Lon 25")
    }

    static func testWaypointValidation() {
        print("Testing Waypoint 5-letter validation...")
        assertTrue(Waypoint.isValidFiveLetterIdent("DIVKO"), "DIVKO is valid")
        assertTrue(Waypoint.isValidFiveLetterIdent("IGSOM"), "IGSOM is valid")
        assertTrue(Waypoint.isValidFiveLetterIdent("OMSUN"), "OMSUN is valid")
        assertTrue(Waypoint.isValidFiveLetterIdent("DOLAT"), "DOLAT is valid")
        assertTrue(Waypoint.isValidFiveLetterIdent("KOIVU"), "KOIVU is valid")
        assertTrue(!Waypoint.isValidFiveLetterIdent("TN093"), "TN093 with digits is REJECTED")
        assertTrue(!Waypoint.isValidFiveLetterIdent("K1234"), "K1234 with digits is REJECTED")
        assertTrue(!Waypoint.isValidFiveLetterIdent("HEL"), "3-letter not valid")
        assertTrue(!Waypoint.isValidFiveLetterIdent("EFHK"), "4-letter not valid")
        assertTrue(!Waypoint.isValidFiveLetterIdent("DIVKO1"), "6-letter not valid")
    }

    static func testAirportMetadataAndSearch() {
        print("Testing AirportMetadata and Search...")
        let othhMeta = AirportMetadata.shared.lookup("OTHH")
        assertTrue(othhMeta != nil, "Found OTHH metadata")
        assertEqual(othhMeta?.i, "DOH", "OTHH IATA is DOH")
        assertTrue(othhMeta?.c.contains("Doha") == true, "OTHH city contains Doha")

        let efhkMeta = AirportMetadata.shared.lookup("EFHK")
        assertTrue(efhkMeta != nil, "Found EFHK metadata")
        assertEqual(efhkMeta?.i, "HEL", "EFHK IATA is HEL")

        let apt1 = Airport(id: "OTHH", iata: "DOH", name: "Hamad International Airport", city: "Doha", latitude: 25.27, longitude: 51.60)
        let apt2 = Airport(id: "EFHK", iata: "HEL", name: "Helsinki Vantaa Airport", city: "Helsinki", latitude: 60.31, longitude: 24.96)
        assertEqual(apt1.displayText, "OTHH (DOH) - Hamad International Airport")
        assertEqual(apt2.displayText, "EFHK (HEL) - Helsinki Vantaa Airport")
    }

    @MainActor
    static func testOptimalRouteOrdering() {
        print("Testing Optimal Detour Route Ordering...")
        let state = AppState.shared
        state.clearAll()

        state.originAirport = Airport(id: "OTHH", iata: "DOH", name: "Hamad", city: "Doha", latitude: 25.27, longitude: 51.60)
        state.destinationAirport = Airport(id: "EFHK", iata: "HEL", name: "Helsinki", city: "Helsinki", latitude: 60.31, longitude: 24.96)

        // Coordinates:
        // LUNIT: lat 56.17 (south)
        // DOLAT: lat 58.01 (middle)
        // KOIVU: lat 59.84 (north)
        let lunit = RoutePoint(ident: "LUNIT", latitude: 56.175, longitude: 25.158, kind: .waypoint("LUNIT"))
        let dolat = RoutePoint(ident: "DOLAT", latitude: 58.010, longitude: 24.983, kind: .waypoint("DOLAT"))
        let koivu = RoutePoint(ident: "KOIVU", latitude: 59.844, longitude: 24.665, kind: .waypoint("KOIVU"))

        // Insert out of order: DOLAT first, then LUNIT, then KOIVU
        state.insertRoutePointOptimal(dolat)
        state.insertRoutePointOptimal(lunit)
        state.insertRoutePointOptimal(koivu)

        let idents = state.routePoints.map { $0.ident }
        print("  Resulting Route Order:", idents)
        assertEqual(idents, ["LUNIT", "DOLAT", "KOIVU"], "Points ordered along flight progression from South to North")
        assertEqual(state.routeString, "LUNIT DOLAT KOIVU", "Copied route string matches flight progression")
    }

    static func testSpatialKDTree() {
        print("Testing SpatialKDTree...")
        let wpts = [
            Waypoint(id: "DIVKO", latitude: 60.0, longitude: 25.0),
            Waypoint(id: "RATSU", latitude: 59.0, longitude: 25.2),
            Waypoint(id: "RUNIX", latitude: 58.0, longitude: 25.5),
            Waypoint(id: "OBVUS", latitude: 57.0, longitude: 25.8)
        ]

        let tree = SpatialKDTree(waypoints: wpts)
        assertEqual(tree.count, 4, "Tree count")

        // Query near RATSU (59.05, 25.22)
        let nearest = tree.findNearest(to: 59.05, targetLon: 25.22, maxDistanceMeters: 50000.0)
        assertTrue(nearest != nil, "Found nearest")
        assertEqual(nearest?.waypoint.id, "RATSU", "Nearest is RATSU")
    }

    static func testSnappingEngine() {
        print("Testing SnappingEngine...")
        // 1. Test straight stroke from VAKIR to TUNGA with ULKIL and ADIDU nearby
        let wpts = [
            Waypoint(id: "VAKIR", latitude: 55.3364, longitude: 23.9003),
            Waypoint(id: "ULKIL", latitude: 54.8747, longitude: 23.9914), // ~10nm east of track
            Waypoint(id: "ADIDU", latitude: 54.5303, longitude: 23.6343), // ~4nm west of track
            Waypoint(id: "TUNGA", latitude: 54.2264, longitude: 23.3839)
        ]
        let tree = SpatialKDTree(waypoints: wpts)
        let engine = SnappingEngine(snappingRadiusNauticalMiles: 50.0)

        // Hand-drawn roughly straight stroke directly from VAKIR to TUNGA
        let straightStroke = [
            CLLocationCoordinate2D(latitude: 55.3364, longitude: 23.9003),
            CLLocationCoordinate2D(latitude: 55.0, longitude: 23.75),
            CLLocationCoordinate2D(latitude: 54.6, longitude: 23.55),
            CLLocationCoordinate2D(latitude: 54.2264, longitude: 23.3839)
        ]

        let route = engine.snapStroke(straightStroke, using: tree)
        let idents = route.map { $0.ident }
        print("  Straight stroke snapped idents:", idents)
        assertEqual(idents, ["VAKIR", "TUNGA"], "Straight stroke must directly connect VAKIR to TUNGA without spurious intermediate waypoints")
    }

    static func testBGLReaderBasics() {
        print("Testing BGLReader...")
        let sampleURL = URL(fileURLWithPath: "data/2606/navigraph-nav-base/scenery/fs-base/scenery/1002/APX82180.bgl")
        if FileManager.default.fileExists(atPath: sampleURL.path) {
            let reader = BGLReader()
            let parsed = reader.readFile(at: sampleURL, parseAirports: true, parseWaypoints: false)
            assertTrue(parsed.airports.count >= 1, "Parsed airport count >= 1")
            let rktl = parsed.airports.first(where: { $0.id == "RKTL" })
            assertTrue(rktl != nil, "Found RKTL")
            assertEqual(rktl?.name, "Uljin", "RKTL name is Uljin")
        } else {
            print("  Skipping BGL file test: sample file not found")
        }
    }
}
