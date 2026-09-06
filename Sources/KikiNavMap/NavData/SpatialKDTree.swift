import Foundation

public final class SpatialKDTree: @unchecked Sendable {

    private final class Node {
        let waypoint: Waypoint
        let axis: Int // 0 for lat, 1 for lon
        var left: Node?
        var right: Node?

        init(waypoint: Waypoint, axis: Int) {
            self.waypoint = waypoint
            self.axis = axis
        }
    }

    private var root: Node?
    public private(set) var count: Int = 0

    public init(waypoints: [Waypoint] = []) {
        build(waypoints: waypoints)
    }

    public func build(waypoints: [Waypoint]) {
        self.count = waypoints.count
        var array = waypoints
        self.root = buildRecursive(&array, start: 0, end: array.count, depth: 0)
    }

    private func buildRecursive(_ array: inout [Waypoint], start: Int, end: Int, depth: Int) -> Node? {
        guard start < end else { return nil }
        let axis = depth % 2

        let mid = (start + end) / 2
        quickSelect(&array, start: start, end: end, k: mid, axis: axis)

        let node = Node(waypoint: array[mid], axis: axis)
        node.left = buildRecursive(&array, start: start, end: mid, depth: depth + 1)
        node.right = buildRecursive(&array, start: mid + 1, end: end, depth: depth + 1)
        return node
    }

    private func quickSelect(_ array: inout [Waypoint], start: Int, end: Int, k: Int, axis: Int) {
        var left = start
        var right = end - 1
        while left < right {
            let pivotIdx = partition(&array, left: left, right: right, axis: axis)
            if pivotIdx == k {
                return
            } else if pivotIdx < k {
                left = pivotIdx + 1
            } else {
                right = pivotIdx - 1
            }
        }
    }

    private func partition(_ array: inout [Waypoint], left: Int, right: Int, axis: Int) -> Int {
        let pivot = array[right]
        var i = left
        for j in left..<right {
            let compareValue = (axis == 0) ? (array[j].latitude <= pivot.latitude) : (array[j].longitude <= pivot.longitude)
            if compareValue {
                array.swapAt(i, j)
                i += 1
            }
        }
        array.swapAt(i, right)
        return i
    }

    // MARK: - Distance Approximation (Equirectangular in meters)
    public static func distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180.0
        let midLat = (lat1 + lat2) * 0.5 * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0 * cos(midLat)
        let R = 6371000.0 // Earth radius in meters
        return sqrt(dLat * dLat + dLon * dLon) * R
    }

    public static func metersToNauticalMiles(_ meters: Double) -> Double {
        return meters / 1852.0
    }

    public static func nauticalMilesToMeters(_ nm: Double) -> Double {
        return nm * 1852.0
    }

    // MARK: - Nearest Neighbor Query
    public func findNearest(to targetLat: Double, targetLon: Double, maxDistanceMeters: Double = .infinity) -> (waypoint: Waypoint, distance: Double)? {
        guard let root = root else { return nil }

        var bestWpt: Waypoint? = nil
        var bestDist = maxDistanceMeters

        func search(_ node: Node?) {
            guard let node = node else { return }

            let d = Self.distanceMeters(lat1: targetLat, lon1: targetLon, lat2: node.waypoint.latitude, lon2: node.waypoint.longitude)
            if d < bestDist {
                bestDist = d
                bestWpt = node.waypoint
            }

            let coordDiff = (node.axis == 0) ? (targetLat - node.waypoint.latitude) : (targetLon - node.waypoint.longitude)
            // 1 degree ~ 111,000 meters
            let axisDistMeters = abs(coordDiff) * 111000.0

            let first = coordDiff < 0 ? node.left : node.right
            let second = coordDiff < 0 ? node.right : node.left

            search(first)
            if axisDistMeters < bestDist {
                search(second)
            }
        }

        search(root)
        if let bestWpt = bestWpt {
            return (bestWpt, bestDist)
        }
        return nil
    }

    // MARK: - Range Query
    public func findInRadius(centerLat: Double, centerLon: Double, radiusMeters: Double) -> [Waypoint] {
        guard let root = root else { return [] }
        var results: [Waypoint] = []

        func search(_ node: Node?) {
            guard let node = node else { return }

            let d = Self.distanceMeters(lat1: centerLat, lon1: centerLon, lat2: node.waypoint.latitude, lon2: node.waypoint.longitude)
            if d <= radiusMeters {
                results.append(node.waypoint)
            }

            let coordDiff = (node.axis == 0) ? (centerLat - node.waypoint.latitude) : (centerLon - node.waypoint.longitude)
            let axisDistMeters = abs(coordDiff) * 111000.0

            let first = coordDiff < 0 ? node.left : node.right
            let second = coordDiff < 0 ? node.right : node.left

            search(first)
            if axisDistMeters <= radiusMeters {
                search(second)
            }
        }

        search(root)
        return results
    }
}
