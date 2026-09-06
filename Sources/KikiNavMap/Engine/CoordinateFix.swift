import Foundation

public struct CoordinateFix: Sendable {
    /// Formats latitude and longitude into flight plan coordinate fix format, e.g. "60N120W"
    public static func format(latitude: Double, longitude: Double) -> String {
        let latRound = Int(round(latitude))
        let lonRound = Int(round(longitude))

        let latDir = latRound >= 0 ? "N" : "S"
        let lonDir = lonRound >= 0 ? "E" : "W"

        let latStr = String(format: "%02d", abs(latRound))
        let lonStr = String(format: "%03d", abs(lonRound))

        return "\(latStr)\(latDir)\(lonStr)\(lonDir)"
    }

    /// Parses string like "60N120W", "61N130W", "58N025E"
    public static func parse(_ str: String) -> (Double, Double)? {
        let clean = str.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Regex: ^(\d{2})([NS])(\d{3})([EW])$
        guard clean.count == 7 else { return nil }
        
        let chars = Array(clean)
        guard let latVal = Double(String(chars[0..<2])),
              let lonVal = Double(String(chars[3..<6])) else {
            return nil
        }
        
        let latSign = (chars[2] == "S") ? -1.0 : 1.0
        let lonSign = (chars[6] == "W") ? -1.0 : 1.0
        
        return (latVal * latSign, lonVal * lonSign)
    }
}
