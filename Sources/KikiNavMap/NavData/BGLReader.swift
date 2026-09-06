import Foundation

public final class BGLReader: Sendable {

    public init() {}

    // MARK: - Coordinate Conversion
    public static func intToLonX(_ lonX: Int32) -> Double {
        return (Double(lonX) * (360.0 / (3.0 * 268435456.0))) - 180.0
    }

    public static func intToLatY(_ latY: Int32) -> Double {
        return 90.0 - Double(latY) * (180.0 / (2.0 * 268435456.0))
    }

    // MARK: - Base-38 ICAO Decoder
    public static func intToIcao(_ rawValue: UInt64, numChars: Int = 8, bitShift: Int = 6) -> String {
        var value = rawValue >> bitShift
        if value == 0 { return "" }

        var coded: [UInt64] = []
        while value > 37 {
            let rem = value % 38
            coded.append(rem)
            value = (value - rem) / 38
        }
        coded.append(value)

        var chars: [Character] = []
        for c in coded.prefix(numChars) {
            if c == 0 { break }
            if c >= 2 && c < 12 {
                chars.append(Character(UnicodeScalar(UInt8(48 + (c - 2))))) // '0' + (c - 2)
            } else if c >= 12 && c <= 37 {
                chars.append(Character(UnicodeScalar(UInt8(65 + (c - 12))))) // 'A' + (c - 12)
            }
        }
        chars.reverse()
        return String(chars)
    }

    public static func intToIcao32(_ rawValue: UInt32, numChars: Int = 5, bitShift: Int = 5) -> String {
        return intToIcao(UInt64(rawValue), numChars: numChars, bitShift: bitShift)
    }

    // MARK: - Read Single BGL File
    public struct ParsedBGLData: Sendable {
        public let airports: [Airport]
        public let waypoints: [Waypoint]
    }

    public func readFile(at url: URL, parseAirports: Bool = true, parseWaypoints: Bool = true) -> ParsedBGLData {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return ParsedBGLData(airports: [], waypoints: [])
        }
        guard data.count >= 56 else {
            return ParsedBGLData(airports: [], waypoints: [])
        }

        return data.withUnsafeBytes { rawBuffer -> ParsedBGLData in
            guard let ptr = rawBuffer.baseAddress else {
                return ParsedBGLData(airports: [], waypoints: [])
            }

            let magic = ptr.load(fromByteOffset: 0, as: UInt32.self)
            guard magic == 0x19920201 else {
                return ParsedBGLData(airports: [], waypoints: [])
            }

            let numSections = Int(ptr.load(fromByteOffset: 20, as: UInt32.self))
            guard numSections > 0 && 56 + numSections * 20 <= data.count else {
                return ParsedBGLData(airports: [], waypoints: [])
            }

            var parsedAirports: [Airport] = []
            var parsedWaypoints: [Waypoint] = []

            for s in 0..<numSections {
                let secOffset = 56 + s * 20
                let secType = ptr.load(fromByteOffset: secOffset, as: UInt32.self)
                let secFlags = ptr.load(fromByteOffset: secOffset + 4, as: UInt32.self)
                let numSub = Int(ptr.load(fromByteOffset: secOffset + 8, as: UInt32.self))
                let subOffset = Int(ptr.load(fromByteOffset: secOffset + 12, as: UInt32.self))

                let subSize = Int(((secFlags & 0x10000) | 0x40000) >> 0x0E)
                guard subSize >= 16, numSub > 0, subOffset + numSub * subSize <= data.count else {
                    continue
                }

                if parseAirports && (secType == 0x03 || secType == 0x3C) {
                    // Airport section
                    for subIdx in 0..<numSub {
                        let currentSub = subOffset + subIdx * subSize
                        let numRecs = Int(ptr.load(fromByteOffset: currentSub + 4, as: UInt32.self))
                        let recOffset = Int(ptr.load(fromByteOffset: currentSub + 8, as: UInt32.self))

                        var curOffset = recOffset
                        var rCount = 0
                        while rCount < numRecs && curOffset + 6 <= data.count {
                            let recId = ptr.load(fromByteOffset: curOffset, as: UInt16.self)
                            let recSize = Int(ptr.load(fromByteOffset: curOffset + 2, as: UInt32.self))
                            guard recSize >= 6 && curOffset + recSize <= data.count else { break }

                            let bodyOffset = curOffset + 6
                            let bodyLen = recSize - 6

                            if recId == 0x0113 && bodyLen >= 78 { // MSFS 2024 Airport
                                let lonX = ptr.load(fromByteOffset: bodyOffset + 6, as: Int32.self)
                                let latY = ptr.load(fromByteOffset: bodyOffset + 10, as: Int32.self)
                                let altMm = ptr.load(fromByteOffset: bodyOffset + 14, as: Int32.self)
                                let icaoU64 = ptr.load(fromByteOffset: bodyOffset + 70, as: UInt64.self)

                                let icao = Self.intToIcao(icaoU64, numChars: 8, bitShift: 6)
                                if icao.count == 4 {
                                    // Parse name subrecord (0x0019) starting around offset 86
                                    var name = ""
                                    var subRecOff = bodyOffset + 86
                                    while subRecOff + 6 <= bodyOffset + bodyLen {
                                        let sId = ptr.load(fromByteOffset: subRecOff, as: UInt16.self)
                                        let sSz = Int(ptr.load(fromByteOffset: subRecOff + 2, as: UInt32.self))
                                        guard sSz >= 6 && subRecOff + sSz <= bodyOffset + bodyLen else { break }

                                        if sId == 0x0019 {
                                            let strBytes = ptr.advanced(by: subRecOff + 6).assumingMemoryBound(to: UInt8.self)
                                            let maxLen = sSz - 6
                                            var strArr: [UInt8] = []
                                            for i in 0..<maxLen {
                                                let b = strBytes[i]
                                                if b == 0 { break }
                                                strArr.append(b)
                                            }
                                            name = String(bytes: strArr, encoding: .ascii) ?? ""
                                            break
                                        }
                                        subRecOff += sSz
                                    }

                                    let lat = Self.intToLatY(latY)
                                    let lon = Self.intToLonX(lonX)

                                    let meta = AirportMetadata.shared.lookup(icao)
                                    let iata = meta?.i ?? ""
                                    let city = meta?.c ?? ""
                                    let cleanName: String
                                    if name.isEmpty || name.hasPrefix("TT:") {
                                        cleanName = meta?.n.isEmpty == false ? meta!.n : icao
                                    } else {
                                        cleanName = name
                                    }

                                    parsedAirports.append(Airport(
                                        id: icao,
                                        iata: iata,
                                        name: cleanName,
                                        city: city,
                                        latitude: lat,
                                        longitude: lon,
                                        elevationMeters: Double(altMm) / 1000.0
                                    ))
                                }
                            }

                            curOffset += recSize
                            rCount += 1
                        }
                    }
                } else if parseWaypoints && secType == 0x22 {
                    // Waypoint section
                    for subIdx in 0..<numSub {
                        let currentSub = subOffset + subIdx * subSize
                        let numRecs = Int(ptr.load(fromByteOffset: currentSub + 4, as: UInt32.self))
                        let recOffset = Int(ptr.load(fromByteOffset: currentSub + 8, as: UInt32.self))

                        var curOffset = recOffset
                        var rCount = 0
                        while rCount < numRecs && curOffset + 6 <= data.count {
                            let recId = ptr.load(fromByteOffset: curOffset, as: UInt16.self)
                            let recSize = Int(ptr.load(fromByteOffset: curOffset + 2, as: UInt32.self))
                            guard recSize >= 6 && curOffset + recSize <= data.count else { break }

                            let bodyOffset = curOffset + 6
                            let bodyLen = recSize - 6

                            if recId == 0x0108 && bodyLen >= 22 { // MSFS 2024 Waypoint
                                let lonX = ptr.load(fromByteOffset: bodyOffset + 2, as: Int32.self)
                                let latY = ptr.load(fromByteOffset: bodyOffset + 6, as: Int32.self)
                                let icaoU64 = ptr.load(fromByteOffset: bodyOffset + 14, as: UInt64.self)
                                let ident = Self.intToIcao(icaoU64, numChars: 8, bitShift: 6)

                                // Strict requirement: 5-letter fix only!
                                if Waypoint.isValidFiveLetterIdent(ident) {
                                    parsedWaypoints.append(Waypoint(
                                        id: ident,
                                        latitude: Self.intToLatY(latY),
                                        longitude: Self.intToLonX(lonX)
                                    ))
                                }
                            } else if recId == 0x0022 && bodyLen >= 18 { // Standard Waypoint
                                let lonX = ptr.load(fromByteOffset: bodyOffset + 2, as: Int32.self)
                                let latY = ptr.load(fromByteOffset: bodyOffset + 6, as: Int32.self)
                                let icaoU32 = ptr.load(fromByteOffset: bodyOffset + 14, as: UInt32.self)
                                let ident = Self.intToIcao32(icaoU32, numChars: 5, bitShift: 5)

                                if Waypoint.isValidFiveLetterIdent(ident) {
                                    parsedWaypoints.append(Waypoint(
                                        id: ident,
                                        latitude: Self.intToLatY(latY),
                                        longitude: Self.intToLonX(lonX)
                                    ))
                                }
                            }

                            curOffset += recSize
                            rCount += 1
                        }
                    }
                }
            }

            return ParsedBGLData(airports: parsedAirports, waypoints: parsedWaypoints)
        }
    }

    // MARK: - Scan Directory
    public func scanDirectory(at rootURL: URL, parseAirports: Bool, parseWaypoints: Bool) -> ParsedBGLData {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return ParsedBGLData(airports: [], waypoints: [])
        }

        var allAirports: [String: Airport] = [:]
        var allWaypoints: [String: Waypoint] = [:]

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "bgl" {
                let parsed = readFile(at: fileURL, parseAirports: parseAirports, parseWaypoints: parseWaypoints)
                for apt in parsed.airports {
                    allAirports[apt.id] = apt
                }
                for wpt in parsed.waypoints {
                    allWaypoints[wpt.id] = wpt
                }
            }
        }

        return ParsedBGLData(
            airports: Array(allAirports.values).sorted(by: { $0.id < $1.id }),
            waypoints: Array(allWaypoints.values).sorted(by: { $0.id < $1.id })
        )
    }
}
