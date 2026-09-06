import Foundation
import CoreLocation

public final class SnappingEngine: @unchecked Sendable {
    public var snappingRadiusNauticalMiles: Double

    public init(snappingRadiusNauticalMiles: Double = 50.0) {
        self.snappingRadiusNauticalMiles = snappingRadiusNauticalMiles
    }

    public var maxDistanceMeters: Double {
        SpatialKDTree.nauticalMilesToMeters(snappingRadiusNauticalMiles)
    }

    // MARK: - Douglas-Peucker Trajectory Simplification
    public static func perpendicularDistanceMeters(
        p: CLLocationCoordinate2D,
        p1: CLLocationCoordinate2D,
        p2: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = p1.latitude * (.pi / 180.0)
        let lon1 = p1.longitude * (.pi / 180.0)
        let lat2 = p2.latitude * (.pi / 180.0)
        let lon2 = p2.longitude * (.pi / 180.0)
        let lat = p.latitude * (.pi / 180.0)
        let lon = p.longitude * (.pi / 180.0)

        let midLat = (lat1 + lat2) * 0.5
        let cosMid = cos(midLat)

        let x1 = lon1 * cosMid * 6371000.0
        let y1 = lat1 * 6371000.0
        let x2 = lon2 * cosMid * 6371000.0
        let y2 = lat2 * 6371000.0
        let x = lon * cosMid * 6371000.0
        let y = lat * 6371000.0

        let dx = x2 - x1
        let dy = y2 - y1
        let lineLenSq = dx * dx + dy * dy

        if lineLenSq < 1e-6 {
            return hypot(x - x1, y - y1)
        }

        let t = max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / lineLenSq))
        let projX = x1 + t * dx
        let projY = y1 + t * dy
        return hypot(x - projX, y - projY)
    }

    public static func simplifyCoordinates(
        _ points: [CLLocationCoordinate2D],
        epsilonMeters: Double = 12000.0 // ~6.5 NM tolerance for hand-drawn strokes
    ) -> [CLLocationCoordinate2D] {
        guard points.count >= 3 else { return points }

        var dmax = 0.0
        var index = 0
        let p1 = points[0]
        let p2 = points[points.count - 1]

        for i in 1..<(points.count - 1) {
            let d = perpendicularDistanceMeters(p: points[i], p1: p1, p2: p2)
            if d > dmax {
                index = i
                dmax = d
            }
        }

        if dmax > epsilonMeters {
            let left = simplifyCoordinates(Array(points[0...index]), epsilonMeters: epsilonMeters)
            let right = simplifyCoordinates(Array(points[index..<points.count]), epsilonMeters: epsilonMeters)
            return Array(left.dropLast()) + right
        } else {
            return [p1, p2]
        }
    }

    /// Snaps a hand-drawn geographical stroke to a sequence of 5-letter waypoints,
    /// prioritizing strict adherence to the user's drawn path rather than inserting detours.
    public func snapStroke(
        _ strokeCoordinates: [CLLocationCoordinate2D],
        using kdTree: SpatialKDTree
    ) -> [RoutePoint] {
        guard strokeCoordinates.count >= 2, kdTree.count > 0 else { return [] }

        // 1. Simplify the hand-drawn stroke with Douglas-Peucker.
        // If user drew a straight line (e.g. VAKIR to TUNGA), this produces exactly [start, end].
        // If user drew deliberate bends/curves around an airspace, it retains only the inflection vertices.
        let keyVertices = Self.simplifyCoordinates(strokeCoordinates, epsilonMeters: 12000.0)

        // 2. Snap each key vertex to nearest 5-letter fix or coordinate
        var routePoints: [RoutePoint] = []
        var visitedIdentSet = Set<String>()

        for pt in keyVertices {
            if let result = kdTree.findNearest(
                to: pt.latitude,
                targetLon: pt.longitude,
                maxDistanceMeters: maxDistanceMeters
            ), Waypoint.isValidFiveLetterIdent(result.waypoint.id) {
                let wpt = result.waypoint
                if let last = routePoints.last, last.ident == wpt.id {
                    continue
                }
                if !visitedIdentSet.contains(wpt.id) {
                    visitedIdentSet.insert(wpt.id)
                    routePoints.append(RoutePoint(
                        ident: wpt.id,
                        latitude: wpt.latitude,
                        longitude: wpt.longitude,
                        kind: .waypoint(wpt.id)
                    ))
                }
            } else {
                let code = CoordinateFix.format(latitude: pt.latitude, longitude: pt.longitude)
                if let last = routePoints.last, last.ident == code {
                    continue
                }
                if !visitedIdentSet.contains(code) {
                    visitedIdentSet.insert(code)
                    routePoints.append(RoutePoint(
                        ident: code,
                        latitude: pt.latitude,
                        longitude: pt.longitude,
                        kind: .coordinate(code)
                    ))
                }
            }
        }

        return routePoints
    }

    /// Snap an individually dragged point to the nearest 5-letter fix
    public func snapIndividualPoint(
        latitude: Double,
        longitude: Double,
        using kdTree: SpatialKDTree
    ) -> (ident: String, lat: Double, lon: Double)? {
        guard let result = kdTree.findNearest(
            to: latitude,
            targetLon: longitude,
            maxDistanceMeters: maxDistanceMeters
        ) else {
            return nil
        }
        let wpt = result.waypoint
        guard Waypoint.isValidFiveLetterIdent(wpt.id) else { return nil }
        return (wpt.id, wpt.latitude, wpt.longitude)
    }
}
