import Foundation
import CoreLocation

/// Represents a historical or active flight instance retrieved from real-world tracking.
public struct TrackedFlightSchedule: Identifiable, Sendable, Hashable {
    public var id: String { kmlURL.absoluteString }
    public let flightIdent: String
    public let dateString: String         // e.g. "20260917" or "2026-09-17"
    public let departureICAO: String       // e.g. "EHAM"
    public let arrivalICAO: String         // e.g. "FAOR"
    public let departureTimeUTC: String    // e.g. "0845Z"
    public let aircraftRegistration: String? // e.g. "PH-BVU" or "RA-73704"
    public let kmlURL: URL

    public var displayTitle: String {
        let formattedDate: String
        if dateString.count == 8 {
            let y = dateString.prefix(4)
            let m = dateString.dropFirst(4).prefix(2)
            let d = dateString.suffix(2)
            formattedDate = "\(y)-\(m)-\(d)"
        } else {
            formattedDate = dateString
        }

        var regInfo = ""
        if let reg = aircraftRegistration, !reg.isEmpty {
            regInfo = " · \(reg)"
        }
        return "\(formattedDate)  \(departureICAO) → \(arrivalICAO) (\(departureTimeUTC))\(regInfo)"
    }
}

/// Service to query real-world flight tracks and coordinates from open flight trackers.
public actor FlightTrackerService {
    public static let shared = FlightTrackerService()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Common airline 2-letter IATA to 3-letter ICAO prefix mapping.
    private static let iataToIcaoAirlineMap: [String: String] = [
        "KL": "KLM", "MU": "CES", "CA": "CCA", "CZ": "CSN",
        "DL": "DAL", "UA": "UAL", "AA": "AAL", "AF": "AFR",
        "BA": "BAW", "LH": "DLH", "SQ": "SIA", "CX": "CPA",
        "JL": "JAL", "NH": "ANA", "EK": "UAE", "QR": "QTR",
        "EY": "ETD", "TK": "THY", "AY": "FIN", "SK": "SAS",
        "LX": "SWR", "OS": "AUA", "IB": "IBE", "AZ": "ITY",
        "HU": "CHH", "MF": "CXA", "3U": "CSC", "ZH": "CSZ",
        "HO": "DKH", "9C": "CQH", "QF": "QFA", "NZ": "ANZ",
        "SU": "AFL"
    ]

    /// Inverse mapping: 3-letter ICAO to 2-letter IATA prefix.
    private static let icaoToIataAirlineMap: [String: String] = {
        var map: [String: String] = [:]
        for (iata, icao) in iataToIcaoAirlineMap {
            map[icao] = iata
        }
        return map
    }()

    /// Normalizes user flight input (e.g. "kl591" -> "KLM591", "DLH100" -> "DLH100").
    public static func normalizeFlightNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count >= 3 else { return trimmed }

        let chars = Array(trimmed)
        if chars.count >= 3, chars[0].isLetter, chars[1].isLetter, chars[2].isNumber {
            let prefix2 = String(chars[0...1])
            let suffix = String(chars[2...])
            if let icao = iataToIcaoAirlineMap[prefix2] {
                return icao + suffix
            }
        }
        return trimmed
    }

    /// Converts an ICAO flight number to IATA if applicable (e.g. "AFL462" -> "SU462").
    public static func convertToIataFlightNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count >= 4 else { return trimmed }

        let chars = Array(trimmed)
        if chars[0].isLetter, chars[1].isLetter, chars[2].isLetter, chars[3].isNumber {
            let prefix3 = String(chars[0...2])
            let suffix = String(chars[3...])
            if let iata = icaoToIataAirlineMap[prefix3] {
                return iata + suffix
            }
        }
        return trimmed
    }

    /// Fetches available flight instances for a given flight number.
    /// Combines open tracking APIs (Flightradar24 for registrations & FlightAware for open KML endpoints).
    public func fetchAvailableSchedules(for flightNumber: String, targetDate: String? = nil) async throws -> [TrackedFlightSchedule] {
        let icaoIdent = Self.normalizeFlightNumber(flightNumber)
        let iataIdent = Self.convertToIataFlightNumber(flightNumber)
        guard !icaoIdent.isEmpty else { return [] }

        // 1. Fetch schedules from Flightradar24 (provides registration numbers and high-resolution playback tracks)
        var fr24Schedules: [TrackedFlightSchedule] = []
        for q in [iataIdent, icaoIdent] {
            if let results = await fetchFR24Schedules(for: q, targetDate: targetDate), !results.isEmpty {
                fr24Schedules = results
                break
            }
        }

        // Prefer Flightradar24: richer ADS-B coverage bypassing restricted airspace (e.g. Russia/Ukraine/Georgia corridor)
        if !fr24Schedules.isEmpty {
            return fr24Schedules
        }

        // 2. Fallback to FlightAware (standard open KML endpoint)
        var faSchedules: [TrackedFlightSchedule] = []
        if let faResults = try? await fetchFlightAwareSchedules(for: icaoIdent, targetDate: targetDate) {
            faSchedules = faResults
        }

        return faSchedules
    }

    /// Fetches flight schedules directly from Flightradar24.
    private func fetchFR24Schedules(for ident: String, targetDate: String?) async -> [TrackedFlightSchedule]? {
        let urlStr = "https://api.flightradar24.com/common/v1/flight/list.json?query=\(ident)&fetchBy=flight&page=1&limit=50"
        guard let url = URL(string: urlStr) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.flightradar24.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let resp = result["response"] as? [String: Any],
              let flightData = resp["data"] as? [[String: Any]] else {
            return nil
        }

        let normalizedTarget = targetDate?.replacingOccurrences(of: "-", with: "")
        var schedules: [TrackedFlightSchedule] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HHmm'Z'"
        timeFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        for f in flightData {
            let identDict = f["identification"] as? [String: Any]
            let flightId = identDict?["id"] as? String
            let flightNum = (identDict?["number"] as? [String: Any])?["default"] as? String ?? ident
            let aircraft = f["aircraft"] as? [String: Any]
            let reg = aircraft?["registration"] as? String

            let airport = f["airport"] as? [String: Any]
            let orig = ((airport?["origin"] as? [String: Any])?["code"] as? [String: Any])?["icao"] as? String ?? ""
            let dest = ((airport?["destination"] as? [String: Any])?["code"] as? [String: Any])?["icao"] as? String ?? ""

            let timeInfo = f["time"] as? [String: Any]
            let depTimestamp = (timeInfo?["real"] as? [String: Any])?["departure"] as? TimeInterval
                ?? (timeInfo?["scheduled"] as? [String: Any])?["departure"] as? TimeInterval

            guard let depTs = depTimestamp, depTs > 0, !orig.isEmpty, !dest.isEmpty else { continue }
            let depDate = Date(timeIntervalSince1970: depTs)
            let dateStr = dateFormatter.string(from: depDate)
            let timeStr = timeFormatter.string(from: depDate)

            if let target = normalizedTarget, !target.isEmpty && dateStr != target {
                continue
            }

            // Only include flights that have an active/completed flight ID with playback track data
            guard let fId = flightId, !fId.isEmpty,
                  let targetURL = URL(string: "https://api.flightradar24.com/common/v1/flight-playback.json?flightId=\(fId)") else {
                continue
            }

            schedules.append(TrackedFlightSchedule(
                flightIdent: flightNum,
                dateString: dateStr,
                departureICAO: orig,
                arrivalICAO: dest,
                departureTimeUTC: timeStr,
                aircraftRegistration: reg,
                kmlURL: targetURL
            ))
        }

        return schedules.sorted { ($0.dateString, $0.departureTimeUTC) > ($1.dateString, $1.departureTimeUTC) }
    }

    /// Fetches flight schedules from FlightAware HTML page.
    private func fetchFlightAwareSchedules(for ident: String, targetDate: String?) async throws -> [TrackedFlightSchedule] {
        let urlString = "https://www.flightaware.com/live/flight/\(ident)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let html = String(decoding: data, as: UTF8.self)
        return Self.parseFlightSchedules(from: html, defaultIdent: ident, targetDate: targetDate)
    }

    /// Parses tracklog and Google Earth URLs from the FlightAware HTML page.
    public static func parseFlightSchedules(from html: String, defaultIdent: String, targetDate: String? = nil) -> [TrackedFlightSchedule] {
        let pattern = #"/live/flight/([A-Za-z0-9_]+)/history/([0-9]{8})/([0-9A-Za-z]+)/([A-Za-z]{3,4})/([A-Za-z]{3,4})/(?:tracklog|google_earth)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        let nsHtml = html as NSString
        // Extract aircraft registration from trackpollBootstrap if available
        var regMap: [String: String] = [:]
        let jsonPattern = #"var trackpollBootstrap\s*=\s*(\{.*?\});\s*(?:var|</script>)"#
        if let jsonRegex = try? NSRegularExpression(pattern: jsonPattern, options: .dotMatchesLineSeparators),
           let jsonMatch = jsonRegex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsHtml.length)),
           jsonMatch.numberOfRanges >= 2 {
            let jsonStr = nsHtml.substring(with: jsonMatch.range(at: 1))
            if let jsonData = jsonStr.data(using: .utf8),
               let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let flights = root["flights"] as? [String: [String: Any]] {
                for (_, fval) in flights {
                    let links = fval["links"] as? [String: Any]
                    let trackPath = (links?["trackLog"] as? String) ?? (links?["permanent"] as? String) ?? ""
                    let aircraft = fval["aircraft"] as? [String: Any]
                    let tail = (aircraft?["tail"] as? String) ?? (fval["tailNumber"] as? String)
                    if !trackPath.isEmpty, let t = tail, !t.isEmpty {
                        regMap[trackPath] = t
                    }
                }
            }
        }

        let normalizedTargetDate = targetDate?.replacingOccurrences(of: "-", with: "")
        var results: [TrackedFlightSchedule] = []
        var seenKeys = Set<String>()

        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHtml.length))

        for match in matches {
            guard match.numberOfRanges >= 6 else { continue }
            let ident = nsHtml.substring(with: match.range(at: 1))
            let dateStr = nsHtml.substring(with: match.range(at: 2))
            let timeStr = nsHtml.substring(with: match.range(at: 3))
            let origin = nsHtml.substring(with: match.range(at: 4)).uppercased()
            let dest = nsHtml.substring(with: match.range(at: 5)).uppercased()

            if let filter = normalizedTargetDate, !filter.isEmpty && dateStr != filter {
                continue
            }

            let uniqueKey = "\(dateStr)_\(timeStr)_\(origin)_\(dest)"
            if seenKeys.contains(uniqueKey) {
                continue
            }
            seenKeys.insert(uniqueKey)

            let trackPath = "/live/flight/\(ident)/history/\(dateStr)/\(timeStr)/\(origin)/\(dest)/tracklog"
            let reg = regMap[trackPath]

            let kmlUrlStr = "https://www.flightaware.com/live/flight/\(ident)/history/\(dateStr)/\(timeStr)/\(origin)/\(dest)/google_earth"
            if let kmlURL = URL(string: kmlUrlStr) {
                results.append(TrackedFlightSchedule(
                    flightIdent: ident,
                    dateString: dateStr,
                    departureICAO: origin,
                    arrivalICAO: dest,
                    departureTimeUTC: timeStr,
                    aircraftRegistration: reg,
                    kmlURL: kmlURL
                ))
            }
        }

        return results.sorted { ($0.dateString, $0.departureTimeUTC) > ($1.dateString, $1.departureTimeUTC) }
    }

    /// Fetches and parses radar track coordinates from either Flightradar24 playback JSON or FlightAware Google Earth KML.
    public func fetchTrackCoordinates(from trackURL: URL) async throws -> (originICAO: String, destICAO: String, coordinates: [CLLocationCoordinate2D]) {
        if trackURL.host?.contains("flightradar24.com") == true {
            var request = URLRequest(url: trackURL)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.flightradar24.com/", forHTTPHeaderField: "Referer")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            if let (data, response) = try? await session.data(for: request),
               let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = root["result"] as? [String: Any],
               let resp = result["response"] as? [String: Any],
               let flightObj = (resp["data"] as? [String: Any])?["flight"] as? [String: Any],
               let trackPoints = flightObj["track"] as? [[String: Any]] {
                var coords: [CLLocationCoordinate2D] = []
                coords.reserveCapacity(trackPoints.count)
                for pt in trackPoints {
                    if let lat = pt["latitude"] as? Double, let lon = pt["longitude"] as? Double {
                        coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    }
                }
                let airport = flightObj["airport"] as? [String: Any]
                let orig = ((airport?["origin"] as? [String: Any])?["code"] as? [String: Any])?["icao"] as? String ?? ""
                let dest = ((airport?["destination"] as? [String: Any])?["code"] as? [String: Any])?["icao"] as? String ?? ""

                if coords.count >= 2 {
                    return (orig, dest, coords)
                }
            }
        }

        // Fallback or FlightAware KML endpoint
        var request = URLRequest(url: trackURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let kmlString = String(decoding: data, as: UTF8.self)
        return try Self.parseKMLCoordinates(from: kmlString)
    }

    /// Parses coordinates and origin/destination from KML XML.
    public static func parseKMLCoordinates(from kmlString: String) throws -> (originICAO: String, destICAO: String, coordinates: [CLLocationCoordinate2D]) {
        let coordPattern = #"<gx:coord>\s*([0-9.\-]+)\s+([0-9.\-]+)\s+[0-9.\-]+\s*</gx:coord>"#
        guard let coordRegex = try? NSRegularExpression(pattern: coordPattern, options: []) else {
            throw URLError(.cannotParseResponse)
        }

        let nsKml = kmlString as NSString
        let matches = coordRegex.matches(in: kmlString, options: [], range: NSRange(location: 0, length: nsKml.length))

        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(matches.count)

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let lonStr = nsKml.substring(with: match.range(at: 1))
            let latStr = nsKml.substring(with: match.range(at: 2))
            if let lon = Double(lonStr), let lat = Double(latStr) {
                coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }

        var origin = ""
        var dest = ""
        let namePattern = #"\(([A-Z]{3,4}\s*/\s*)?([A-Z]{4})\s*-\s*([A-Z]{3,4}\s*/\s*)?([A-Z]{4})\)"#
        if let nameRegex = try? NSRegularExpression(pattern: namePattern, options: []),
           let match = nameRegex.firstMatch(in: kmlString, options: [], range: NSRange(location: 0, length: nsKml.length)) {
            if match.numberOfRanges >= 5 {
                origin = nsKml.substring(with: match.range(at: 2))
                dest = nsKml.substring(with: match.range(at: 4))
            }
        }

        return (origin, dest, coords)
    }
}
