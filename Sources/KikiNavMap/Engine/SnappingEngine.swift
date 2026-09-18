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

    // MARK: - Real-World Radar Track Auto-Fitting (Unrestricted Nav Ident & Compression)
    /// Compresses and fits dense real-world radar points into high-altitude route waypoints,
    /// supporting VORs, NDBs, and fixes (2-5 letters) from the local database.
    /// Accurately preserves track segments and leaves track gaps (broken/dashed radar tracks) as direct legs for manual editing.
    public func fitRealWorldFlightTrack(
        _ rawCoordinates: [CLLocationCoordinate2D],
        originCoord: CLLocationCoordinate2D? = nil,
        destCoord: CLLocationCoordinate2D? = nil,
        using kdTree: SpatialKDTree
    ) -> [RoutePoint] {
        guard rawCoordinates.count >= 2 else { return [] }

        // 1. Detect large gaps in radar track (> 80 NM between consecutive points)
        // and split into continuous track segments to accurately process segments and leave gaps direct ("断掉的地方做成直达")
        let gapThresholdMeters = SpatialKDTree.nauticalMilesToMeters(80.0)
        var segments: [[CLLocationCoordinate2D]] = []
        var currentSegment: [CLLocationCoordinate2D] = [rawCoordinates[0]]

        for i in 1..<rawCoordinates.count {
            let p1 = rawCoordinates[i - 1]
            let p2 = rawCoordinates[i]
            let dist = SpatialKDTree.distanceMeters(lat1: p1.latitude, lon1: p1.longitude, lat2: p2.latitude, lon2: p2.longitude)
            if dist > gapThresholdMeters {
                if currentSegment.count >= 2 {
                    segments.append(currentSegment)
                }
                currentSegment = [p2]
            } else {
                currentSegment.append(p2)
            }
        }
        if currentSegment.count >= 2 {
            segments.append(currentSegment)
        }

        if segments.isEmpty {
            segments = [rawCoordinates]
        }

        let terminalThresholdMeters = SpatialKDTree.nauticalMilesToMeters(15.0)
        let epsilonMeters = SpatialKDTree.nauticalMilesToMeters(1.8) // Tight epsilon to capture true airway turns
        let navAidSnappingRadiusMeters = SpatialKDTree.nauticalMilesToMeters(18.0) // Realistic corridor snapping radius avoiding distant detours
        let minSpacingMeters = SpatialKDTree.nauticalMilesToMeters(12.0)

        var routePoints: [RoutePoint] = []
        var visitedIdentSet = Set<String>()

        for (segIndex, seg) in segments.enumerated() {
            var filteredSegment = seg

            // Terminal filtering: only filter origin if this is the first segment and close to origin
            if segIndex == 0, let origin = originCoord {
                filteredSegment.removeAll { pt in
                    SpatialKDTree.distanceMeters(lat1: pt.latitude, lon1: pt.longitude, lat2: origin.latitude, lon2: origin.longitude) < terminalThresholdMeters
                }
            }
            // Terminal filtering: only filter dest if this is the last segment and close to dest
            if segIndex == segments.count - 1, let dest = destCoord {
                filteredSegment.removeAll { pt in
                    SpatialKDTree.distanceMeters(lat1: pt.latitude, lon1: pt.longitude, lat2: dest.latitude, lon2: dest.longitude) < terminalThresholdMeters
                }
            }

            guard filteredSegment.count >= 2 else { continue }

            // Douglas-Peucker simplification with tight 1.8 NM tolerance
            let vertices = Self.simplifyCoordinates(filteredSegment, epsilonMeters: epsilonMeters)

            // Collect candidate points: vertices + intermediate points on long straight segments (> 45 NM)
            var candidatePoints: [(coord: CLLocationCoordinate2D, isVertex: Bool)] = []
            for i in 0..<vertices.count {
                candidatePoints.append((vertices[i], true))

                if i < vertices.count - 1 {
                    let p1 = vertices[i]
                    let p2 = vertices[i + 1]
                    let legDist = SpatialKDTree.distanceMeters(lat1: p1.latitude, lon1: p1.longitude, lat2: p2.latitude, lon2: p2.longitude)
                    let legDistNM = legDist / 1852.0
                    if legDistNM > 45.0 {
                        let steps = Int(legDistNM / 35.0)
                        for s in 1...steps {
                            let frac = Double(s) / Double(steps + 1)
                            let midLat = p1.latitude + frac * (p2.latitude - p1.latitude)
                            let midLon = p1.longitude + frac * (p2.longitude - p1.longitude)
                            candidatePoints.append((CLLocationCoordinate2D(latitude: midLat, longitude: midLon), false))
                        }
                    }
                }
            }

            // Snap candidate points: support all codes (1-5 alphanumeric database navigation aids + coordinate codes)
            for cand in candidatePoints {
                let pt = cand.coord
                if kdTree.count > 0,
                   let result = kdTree.findNearest(to: pt.latitude, targetLon: pt.longitude, maxDistanceMeters: navAidSnappingRadiusMeters),
                   Waypoint.isValidNavIdent(result.waypoint.id) {
                    let wpt = result.waypoint
                    if !visitedIdentSet.contains(wpt.id) {
                        if let lastPt = routePoints.last {
                            let dist = SpatialKDTree.distanceMeters(lat1: lastPt.latitude, lon1: lastPt.longitude, lat2: wpt.latitude, lon2: wpt.longitude)
                            if dist < minSpacingMeters {
                                continue
                            }
                        }
                        visitedIdentSet.insert(wpt.id)
                        routePoints.append(RoutePoint(
                            ident: wpt.id,
                            latitude: wpt.latitude,
                            longitude: wpt.longitude,
                            kind: .waypoint(wpt.id)
                        ))
                    }
                } else if cand.isVertex {
                    // Turn inflection in remote, desert, or oceanic airspace where no navigation aid is nearby:
                    // emit coordinate fix to preserve the smooth flight trajectory without forcing detours to distant fixes!
                    let code = CoordinateFix.format(latitude: pt.latitude, longitude: pt.longitude)
                    if !visitedIdentSet.contains(code) {
                        if let lastPt = routePoints.last {
                            let dist = SpatialKDTree.distanceMeters(lat1: lastPt.latitude, lon1: lastPt.longitude, lat2: pt.latitude, lon2: pt.longitude)
                            if dist < minSpacingMeters {
                                continue
                            }
                        }
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
        }

        return routePoints
    }
}
