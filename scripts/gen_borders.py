import json, base64

with open("Sources/KikiNavMap/Resources/country_labels.json") as f:
    labels = json.load(f)

with open("Sources/KikiNavMap/Resources/borders.bin", "rb") as f:
    b64_borders = base64.b64encode(f.read()).decode("ascii")

with open("Sources/KikiNavMap/NavData/CountryBorders.swift", "w") as out:
    out.write("""import Foundation
import MapKit

public struct CountryLabel: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let coordinate: CLLocationCoordinate2D

    public init(name: String, coordinate: CLLocationCoordinate2D) {
        self.name = name
        self.coordinate = coordinate
    }
}

public final class CountryBorders: @unchecked Sendable {
    public static let shared = CountryBorders()

    public let labels: [CountryLabel]
    public let polylines: [MKPolyline]

    public init() {
        var lbls: [CountryLabel] = []
""")
    for l in labels:
        name = l["name"].replace('"', '\\"')
        lat = l["lat"]
        lon = l["lon"]
        out.write(f'        lbls.append(CountryLabel(name: "{name}", coordinate: CLLocationCoordinate2D(latitude: {lat}, longitude: {lon})))\n')
    
    out.write("""        self.labels = lbls

        let b64 = \"\"\"
""")
    for i in range(0, len(b64_borders), 120):
        out.write(f'        {b64_borders[i:i+120]}\n')
    
    out.write("""        \"\"\"

        var pls: [MKPolyline] = []
        let cleanB64 = b64.replacingOccurrences(of: "\\n", with: "").replacingOccurrences(of: " ", with: "")
        if let data = Data(base64Encoded: cleanB64) {
            data.withUnsafeBytes { raw in
                guard let ptr = raw.baseAddress else { return }
                var offset = 0
                let count = Int(ptr.load(fromByteOffset: offset, as: UInt32.self))
                offset += 4
                for _ in 0..<count {
                    guard offset + 4 <= data.count else { break }
                    let nPts = Int(ptr.load(fromByteOffset: offset, as: UInt32.self))
                    offset += 4
                    guard offset + nPts * 8 <= data.count else { break }
                    var coords: [CLLocationCoordinate2D] = []
                    coords.reserveCapacity(nPts)
                    for _ in 0..<nPts {
                        let lat = Double(ptr.load(fromByteOffset: offset, as: Float.self))
                        let lon = Double(ptr.load(fromByteOffset: offset + 4, as: Float.self))
                        offset += 8
                        coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    }
                    if coords.count >= 2 {
                        let polyline = MKPolyline(coordinates: coords, count: coords.count)
                        pls.append(polyline)
                    }
                }
            }
        }
        self.polylines = pls
    }
}
""")
