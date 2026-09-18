import XCTest
import CoreLocation
@testable import KikiNavMap

final class KikiNavMapTests: XCTestCase {
    static func assertTrue(_ condition: Bool, _ message: String = "") {
        XCTAssertTrue(condition, message)
    }

    static func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "") {
        XCTAssertEqual(a, b, message)
    }

    @MainActor
    func testAll() {
        print("--- Starting KikiNavMap Unit Tests ---")
        Self.testCoordinateFix()
        Self.testWaypointValidation()
        Self.testAirportMetadataAndSearch()
        Self.testOptimalRouteOrdering()
        Self.testSpatialKDTree()
        Self.testSnappingEngine()
        Self.testBGLReaderBasics()
        Self.testFlightTrackerService()
        Self.testRealWorldTrackAutoFittingAndCompression()
        Self.testTrackGapSplitting()
        Self.testManualStrokeStrictFiveLetterPersistence()
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

    static func testFlightTrackerService() {
        print("Testing FlightTrackerService normalization and parsing...")
        assertEqual(FlightTrackerService.normalizeFlightNumber("kl591"), "KLM591", "Normalizing kl591 to KLM591")
        assertEqual(FlightTrackerService.normalizeFlightNumber("mu5101"), "CES5101", "Normalizing mu5101 to CES5101")
        assertEqual(FlightTrackerService.normalizeFlightNumber("dlh100"), "DLH100", "Preserve 3-letter ICAO DLH100")

        // Mock HTML response parsing
        let sampleHTML = """
        <a href="/live/flight/KLM591/history/20260917/0845Z/EHAM/FAOR/tracklog">View Track</a>
        <a href="/live/flight/KLM591/history/20260918/0845Z/EHAM/FAOR/tracklog">View Track</a>
        """
        let schedules = FlightTrackerService.parseFlightSchedules(from: sampleHTML, defaultIdent: "KLM591", targetDate: "20260917")
        assertEqual(schedules.count, 1, "Parsed 1 matching flight schedule for 20260917")
        if let s = schedules.first {
            assertEqual(s.departureICAO, "EHAM", "Origin ICAO EHAM")
            assertEqual(s.arrivalICAO, "FAOR", "Destination ICAO FAOR")
            assertEqual(s.departureTimeUTC, "0845Z", "Time 0845Z")
        }

        // Mock HTML with registration & type
        let sampleHTMLWithBootstrap = """
        <script>
        var trackpollBootstrap = {"flights":{"F1":{"links":{"trackLog":"/live/flight/KLM591/history/20260917/0845Z/EHAM/FAOR/tracklog"},"aircraft":{"type":"B77W","tail":"PH-BVA"}}}};
        </script>
        <a href="/live/flight/KLM591/history/20260917/0845Z/EHAM/FAOR/tracklog">View Track</a>
        """
        let schedulesWithReg = FlightTrackerService.parseFlightSchedules(from: sampleHTMLWithBootstrap, defaultIdent: "KLM591", targetDate: "20260917")
        assertEqual(schedulesWithReg.first?.aircraftRegistration, "PH-BVA", "Parsed registration PH-BVA")

        // Mock KML Coordinate extraction
        let sampleKML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml><Document><name>FlightAware ✈ KLM591 17-Sep-2026 (AMS / EHAM-JNB / FAOR)</name>
        <gx:Track>
            <gx:coord>4.7334 52.2876 168</gx:coord>
            <gx:coord>4.7168 52.2811 404</gx:coord>
            <gx:coord>6.5088 48.9938 9449</gx:coord>
        </gx:Track></Document></kml>
        """
        let parsedKML = try? FlightTrackerService.parseKMLCoordinates(from: sampleKML)
        assertTrue(parsedKML != nil, "Parsed KML successfully")
        assertEqual(parsedKML?.originICAO, "EHAM", "Parsed origin EHAM")
        assertEqual(parsedKML?.destICAO, "FAOR", "Parsed dest FAOR")
        assertEqual(parsedKML?.coordinates.count, 3, "Parsed 3 coordinates")
    }

    static func testRealWorldTrackAutoFittingAndCompression() {
        print("Testing Real-World Track Auto-Fitting and Compression (Relaxing 5-letter)...")

        // Simulate 120 dense radar track points along Europe-Africa corridor
        var radarPoints: [CLLocationCoordinate2D] = []
        for i in 0...120 {
            let fraction = Double(i) / 120.0
            // Route from EHAM (52.3, 4.7) to FAOR (-26.1, 28.2) with a bend around the Mediterranean
            let lat = 52.3 - fraction * 78.4
            let lon = 4.7 + fraction * 23.5 + sin(fraction * .pi) * 3.0 // slight realistic curvature
            radarPoints.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        // Create navigation tree containing 5-letter fixes and 3-letter VORs along the track
        let navPoints = [
            Waypoint(id: "WOODY", latitude: 52.1, longitude: 4.8),
            Waypoint(id: "MEN", latitude: 39.8, longitude: 9.8),     // 3-letter VOR along Mediterranean turn
            Waypoint(id: "FJR", latitude: 31.0, longitude: 13.3),    // 3-letter VOR in North Africa
            Waypoint(id: "DIVKO", latitude: 20.0, longitude: 17.3),
            Waypoint(id: "DIR", latitude: -10.0, longitude: 25.2),   // 3-letter VOR in Central Africa
            Waypoint(id: "AVAGO", latitude: -25.8, longitude: 28.0)
        ]
        let kdTree = SpatialKDTree(waypoints: navPoints)
        let engine = SnappingEngine()

        let origin = CLLocationCoordinate2D(latitude: 52.3, longitude: 4.7)
        let dest = CLLocationCoordinate2D(latitude: -26.1, longitude: 28.2)

        let fittedRoute = engine.fitRealWorldFlightTrack(radarPoints, originCoord: origin, destCoord: dest, using: kdTree)

        print("  Fitted Route Points Count: \(fittedRoute.count) (compressed from 121 radar points)")
        assertTrue(fittedRoute.count >= 2 && fittedRoute.count <= 25, "Compressed from 121 dense points to concise navigation keypoints")

        let idents = fittedRoute.map { $0.ident }
        print("  Fitted Idents:", idents)

        // Verify that 3-letter VORs like MEN or FJR are resolved from the database
        let hasVOR = idents.contains { $0.count < 5 }
        assertTrue(hasVOR, "Automatic mode successfully supports 1-5 letter VORs and fixes from local database")

        // Verify that all returned points are valid codes (either database nav aids or coordinate fixes)
        let allValid = idents.allSatisfy { Waypoint.isValidNavIdent($0) || CoordinateFix.parse($0) != nil }
        assertTrue(allValid, "Automatic mode supports all codes (local nav aids and coordinate codes)")
    }

    static func testTrackGapSplitting() {
        print("Testing Track Gap Splitting (Dashed/Lost Radar Segments)...")
        // Simulate a flight with a huge 600 NM coverage gap in the middle (e.g. Russia/Ukraine border to Turkey)
        var pointsWithGap: [CLLocationCoordinate2D] = []

        // Segment 1 (Moscow area): 5 points
        for i in 0..<5 {
            pointsWithGap.append(CLLocationCoordinate2D(latitude: 55.9 - Double(i) * 0.1, longitude: 37.4 + Double(i) * 0.2))
        }
        // Huge gap: next point is in Turkey (~1000 NM away)
        // Segment 2 (Turkey to Egypt): 10 points
        for i in 0..<10 {
            pointsWithGap.append(CLLocationCoordinate2D(latitude: 38.4 - Double(i) * 1.0, longitude: 32.1 + Double(i) * 0.1))
        }

        let navPoints = [
            Waypoint(id: "SVO01", latitude: 55.6, longitude: 38.0),
            Waypoint(id: "AYT", latitude: 37.4, longitude: 32.2), // VOR in Turkey
            Waypoint(id: "GESON", latitude: 30.4, longitude: 32.9)
        ]
        let kdTree = SpatialKDTree(waypoints: navPoints)
        let engine = SnappingEngine()

        let fitted = engine.fitRealWorldFlightTrack(pointsWithGap, originCoord: CLLocationCoordinate2D(latitude: 55.97, longitude: 37.41), destCoord: CLLocationCoordinate2D(latitude: 27.18, longitude: 33.80), using: kdTree)

        let idents = fitted.map { $0.ident }
        print("  Fitted idents across gap:", idents)

        // Must preserve real waypoints from each continuous segment
        assertTrue(idents.contains("SVO01"), "Contains point from segment 1")
        assertTrue(idents.contains("AYT"), "Contains point from segment 2")

        // Must NOT emit spurious points in the 1000 NM gap between Moscow and Turkey
        let gapPoints = idents.filter { ident in
            if let fix = CoordinateFix.parse(ident) {
                return fix.0 > 40.0 && fix.0 < 54.0 // No fake points in the gap region
            }
            return false
        }
        assertEqual(gapPoints.count, 0, "No spurious points generated inside the tracking gap")
    }

    static func testManualStrokeStrictFiveLetterPersistence() {
        print("Testing Manual Stroke Strict 5-Letter Persistence...")

        // A navigation tree with both 5-letter fix and 3-letter VOR
        let navPoints = [
            Waypoint(id: "MEN", latitude: 39.8, longitude: 4.2),      // 3-letter VOR
            Waypoint(id: "MEDIL", latitude: 39.9, longitude: 4.3)    // 5-letter Fix
        ]
        let kdTree = SpatialKDTree(waypoints: navPoints)
        let engine = SnappingEngine(snappingRadiusNauticalMiles: 50.0)

        // User manually draws stroke near MEN and MEDIL
        let stroke = [
            CLLocationCoordinate2D(latitude: 39.75, longitude: 4.15),
            CLLocationCoordinate2D(latitude: 39.95, longitude: 4.35)
        ]

        let snapped = engine.snapStroke(stroke, using: kdTree)
        let idents = snapped.map { $0.ident }
        print("  Manual hand-drawn stroke snapped idents:", idents)

        // Manual drawing MUST strictly snap to 5-letter fix, ignoring 3-letter MEN
        assertTrue(idents.allSatisfy { Waypoint.isValidFiveLetterIdent($0) || CoordinateFix.parse($0) != nil }, "Manual hand-drawn stroke remains strictly 5-letter or coordinate fix")
        assertTrue(!idents.contains("MEN"), "Manual drawing MUST NOT snap to 3-letter VOR 'MEN'")
    }
}
