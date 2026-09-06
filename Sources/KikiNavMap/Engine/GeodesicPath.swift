import Foundation
import CoreLocation

public struct GeodesicPath: Sendable {
    /// Computes great-circle (geodesic) interpolated coordinates between two points
    public static func interpolate(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        maxSegmentDistanceKm: Double = 100.0
    ) -> [CLLocationCoordinate2D] {
        let lat1 = start.latitude * .pi / 180.0
        let lon1 = start.longitude * .pi / 180.0
        let lat2 = end.latitude * .pi / 180.0
        let lon2 = end.longitude * .pi / 180.0

        // 3D Cartesian coordinates on unit sphere
        let x1 = cos(lat1) * cos(lon1)
        let y1 = cos(lat1) * sin(lon1)
        let z1 = sin(lat1)

        let x2 = cos(lat2) * cos(lon2)
        let y2 = cos(lat2) * sin(lon2)
        let z2 = sin(lat2)

        let dot = max(-1.0, min(1.0, x1 * x2 + y1 * y2 + z1 * z2))
        let angularDistance = acos(dot)

        // Earth radius ~6371 km
        let totalDistanceKm = angularDistance * 6371.0
        if totalDistanceKm < maxSegmentDistanceKm || angularDistance < 1e-6 {
            return [start, end]
        }

        let numSegments = max(2, Int(ceil(totalDistanceKm / maxSegmentDistanceKm)))
        var points: [CLLocationCoordinate2D] = []
        points.reserveCapacity(numSegments + 1)

        let sinD = sin(angularDistance)

        for i in 0...numSegments {
            let f = Double(i) / Double(numSegments)
            let a: Double
            let b: Double

            if abs(sinD) < 1e-7 {
                a = 1.0 - f
                b = f
            } else {
                a = sin((1.0 - f) * angularDistance) / sinD
                b = sin(f * angularDistance) / sinD
            }

            let x = a * x1 + b * x2
            let y = a * y1 + b * y2
            let z = a * z1 + b * z2

            let lat = atan2(z, sqrt(x * x + y * y)) * 180.0 / .pi
            let lon = atan2(y, x) * 180.0 / .pi

            points.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        return points
    }

    /// Computes smooth great-circle connected route across all waypoints
    public static func buildGreatCircleRoute(from keypoints: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard keypoints.count >= 2 else { return keypoints }
        var result: [CLLocationCoordinate2D] = []

        for i in 0..<(keypoints.count - 1) {
            let seg = interpolate(from: keypoints[i], to: keypoints[i + 1], maxSegmentDistanceKm: 60.0)
            if i == 0 {
                result.append(contentsOf: seg)
            } else {
                // Skip duplicate first point of segment
                result.append(contentsOf: seg.dropFirst())
            }
        }

        return result
    }
}
