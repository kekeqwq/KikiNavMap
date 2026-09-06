import Foundation
import Combine
import CoreLocation
import AppKit

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    // MARK: - Selected Airports
    @Published public var originAirport: Airport?
    @Published public var destinationAirport: Airport?
    @Published public var originInputText: String = ""
    @Published public var destinationInputText: String = ""

    // MARK: - Active Route
    @Published public var routePoints: [RoutePoint] = []

    // MARK: - UI & Settings State
    @Published public var isSettingsPresented: Bool = false
    @Published public var isAboutPresented: Bool = false
    @Published public var includeAirportInCopy: Bool = false
    @Published public var snappingRadiusNM: Double = 50.0
    @Published public var useAppleMaps: Bool = true
    @Published public var showCountryBorders: Bool = true

    // MARK: - Snapping Engine
    public let snappingEngine = SnappingEngine()

    public init() {
        self.snappingEngine.snappingRadiusNauticalMiles = snappingRadiusNM
    }

    public var routeString: String {
        let waypointsStr = routePoints.map { $0.ident }.joined(separator: " ")
        if includeAirportInCopy {
            var parts: [String] = []
            if let origin = originAirport { parts.append(origin.id) }
            if !waypointsStr.isEmpty { parts.append(waypointsStr) }
            if let dest = destinationAirport { parts.append(dest.id) }
            return parts.joined(separator: " ")
        } else {
            return waypointsStr
        }
    }

    /// Returns the complete list of key navigation coordinates (Origin -> Waypoints -> Destination)
    public var keypointCoordinates: [CLLocationCoordinate2D] {
        var list: [CLLocationCoordinate2D] = []
        if let origin = originAirport {
            list.append(CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude))
        }
        for pt in routePoints {
            list.append(CLLocationCoordinate2D(latitude: pt.latitude, longitude: pt.longitude))
        }
        if let dest = destinationAirport {
            list.append(CLLocationCoordinate2D(latitude: dest.latitude, longitude: dest.longitude))
        }
        return list
    }

    /// Computes the Great Circle (geodesic) path for map rendering
    public var greatCirclePathCoordinates: [CLLocationCoordinate2D] {
        GeodesicPath.buildGreatCircleRoute(from: keypointCoordinates)
    }

    // MARK: - Actions
    public func selectOrigin(_ airport: Airport) {
        self.originAirport = airport
        self.originInputText = airport.id
    }

    public func selectDestination(_ airport: Airport) {
        self.destinationAirport = airport
        self.destinationInputText = airport.id
    }

    public func clearRoute() {
        self.routePoints.removeAll()
    }

    public func clearAll() {
        self.routePoints.removeAll()
        self.originAirport = nil
        self.destinationAirport = nil
        self.originInputText = ""
        self.destinationInputText = ""
    }

    @discardableResult
    public func copyRouteToClipboard() -> String {
        let text = routeString
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return text
    }

    /// Shift + Click: Point-and-click to snap single nearest 5-letter fix or insert coordinate
    public func handleShiftPointClick(_ coordinate: CLLocationCoordinate2D) {
        let kdTree = NavDataManager.shared.kdTree

        if let result = kdTree.findNearest(
            to: coordinate.latitude,
            targetLon: coordinate.longitude,
            maxDistanceMeters: snappingEngine.maxDistanceMeters
        ), Waypoint.isValidFiveLetterIdent(result.waypoint.id) {
            let wpt = result.waypoint
            let pt = RoutePoint(
                ident: wpt.id,
                latitude: wpt.latitude,
                longitude: wpt.longitude,
                kind: .waypoint(wpt.id)
            )
            insertRoutePointOptimal(pt)
        } else {
            // Far from any waypoint (e.g. oceanic or remote border point): insert coordinate fix!
            let code = CoordinateFix.format(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let pt = RoutePoint(
                ident: code,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                kind: .coordinate(code)
            )
            insertRoutePointOptimal(pt)
        }
    }

    /// Shift + Drag: Freehand drawing that snaps to multiple 5-letter fixes along the path
    public func handleFinishedStroke(_ strokeCoords: [CLLocationCoordinate2D]) {
        let kdTree = NavDataManager.shared.kdTree
        let snapped = snappingEngine.snapStroke(strokeCoords, using: kdTree)
        guard !snapped.isEmpty else { return }

        for pt in snapped {
            insertRoutePointOptimal(pt)
        }
    }

    /// Right-click: Force insert coordinate fix
    public func insertCoordinate(at coordinate: CLLocationCoordinate2D) {
        let code = CoordinateFix.format(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let pt = RoutePoint(
            ident: code,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            kind: .coordinate(code)
        )
        insertRoutePointOptimal(pt)
    }

    /// Inserts a RoutePoint at the geometrically optimal position along the route to eliminate line twists
    public func insertRoutePointOptimal(_ pt: RoutePoint) {
        // Prevent duplicate waypoint in route
        if routePoints.contains(where: { $0.ident == pt.ident }) {
            return
        }

        if routePoints.isEmpty {
            routePoints.append(pt)
            return
        }

        let m = routePoints.count
        var bestSlot = m
        var minDetour = Double.infinity

        for slot in 0...m {
            let detour = computeInsertionDetour(for: pt, atSlot: slot)
            if detour < minDetour {
                minDetour = detour
                bestSlot = slot
            }
        }

        routePoints.insert(pt, at: bestSlot)
    }

    private func computeInsertionDetour(for pt: RoutePoint, atSlot slot: Int) -> Double {
        let m = routePoints.count
        let ptCoord = CLLocationCoordinate2D(latitude: pt.latitude, longitude: pt.longitude)

        if slot == 0 {
            let nextCoord = CLLocationCoordinate2D(latitude: routePoints[0].latitude, longitude: routePoints[0].longitude)
            if let origin = originAirport {
                let origCoord = CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)
                let dOrigToPt = SpatialKDTree.distanceMeters(lat1: origCoord.latitude, lon1: origCoord.longitude, lat2: ptCoord.latitude, lon2: ptCoord.longitude)
                let dPtToNext = SpatialKDTree.distanceMeters(lat1: ptCoord.latitude, lon1: ptCoord.longitude, lat2: nextCoord.latitude, lon2: nextCoord.longitude)
                let dOrigToNext = SpatialKDTree.distanceMeters(lat1: origCoord.latitude, lon1: origCoord.longitude, lat2: nextCoord.latitude, lon2: nextCoord.longitude)
                return dOrigToPt + dPtToNext - dOrigToNext
            } else {
                return SpatialKDTree.distanceMeters(lat1: ptCoord.latitude, lon1: ptCoord.longitude, lat2: nextCoord.latitude, lon2: nextCoord.longitude)
            }
        } else if slot == m {
            let prevCoord = CLLocationCoordinate2D(latitude: routePoints[m - 1].latitude, longitude: routePoints[m - 1].longitude)
            if let dest = destinationAirport {
                let destCoord = CLLocationCoordinate2D(latitude: dest.latitude, longitude: dest.longitude)
                let dPrevToPt = SpatialKDTree.distanceMeters(lat1: prevCoord.latitude, lon1: prevCoord.longitude, lat2: ptCoord.latitude, lon2: ptCoord.longitude)
                let dPtToDest = SpatialKDTree.distanceMeters(lat1: ptCoord.latitude, lon1: ptCoord.longitude, lat2: destCoord.latitude, lon2: destCoord.longitude)
                let dPrevToDest = SpatialKDTree.distanceMeters(lat1: prevCoord.latitude, lon1: prevCoord.longitude, lat2: destCoord.latitude, lon2: destCoord.longitude)
                return dPrevToPt + dPtToDest - dPrevToDest
            } else {
                return SpatialKDTree.distanceMeters(lat1: prevCoord.latitude, lon1: prevCoord.longitude, lat2: ptCoord.latitude, lon2: ptCoord.longitude)
            }
        } else {
            // Between routePoints[slot - 1] and routePoints[slot]
            let prevCoord = CLLocationCoordinate2D(latitude: routePoints[slot - 1].latitude, longitude: routePoints[slot - 1].longitude)
            let nextCoord = CLLocationCoordinate2D(latitude: routePoints[slot].latitude, longitude: routePoints[slot].longitude)
            let dPrevToPt = SpatialKDTree.distanceMeters(lat1: prevCoord.latitude, lon1: prevCoord.longitude, lat2: ptCoord.latitude, lon2: ptCoord.longitude)
            let dPtToNext = SpatialKDTree.distanceMeters(lat1: ptCoord.latitude, lon1: ptCoord.longitude, lat2: nextCoord.latitude, lon2: nextCoord.longitude)
            let dPrevToNext = SpatialKDTree.distanceMeters(lat1: prevCoord.latitude, lon1: prevCoord.longitude, lat2: nextCoord.latitude, lon2: nextCoord.longitude)
            return dPrevToPt + dPtToNext - dPrevToNext
        }
    }

    public func updatePointPosition(id: UUID, newCoordinate: CLLocationCoordinate2D) {
        guard let idx = routePoints.firstIndex(where: { $0.id == id }) else { return }
        var pt = routePoints[idx]

        if pt.isCoordinate {
            let code = CoordinateFix.format(latitude: newCoordinate.latitude, longitude: newCoordinate.longitude)
            pt.ident = code
            pt.latitude = newCoordinate.latitude
            pt.longitude = newCoordinate.longitude
            pt.kind = .coordinate(code)
            routePoints[idx] = pt
        } else {
            let kdTree = NavDataManager.shared.kdTree
            if let snapped = snappingEngine.snapIndividualPoint(
                latitude: newCoordinate.latitude,
                longitude: newCoordinate.longitude,
                using: kdTree
            ) {
                pt.ident = snapped.ident
                pt.latitude = snapped.lat
                pt.longitude = snapped.lon
                pt.kind = .waypoint(snapped.ident)
                routePoints[idx] = pt
            } else {
                pt.latitude = newCoordinate.latitude
                pt.longitude = newCoordinate.longitude
                routePoints[idx] = pt
            }
        }
    }

    public func removeRoutePoint(id: UUID) {
        routePoints.removeAll(where: { $0.id == id })
    }
}
