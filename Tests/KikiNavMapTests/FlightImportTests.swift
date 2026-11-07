import Testing
import Foundation
import CoreLocation
@testable import KikiNavMap

private final class PlaybackProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body: String
        switch request.url!.path {
        case "/valid":
            body = #"{"result":{"response":{"data":{"flight":{"airport":{"origin":{"code":{"icao":"EHAM"}},"destination":{"code":{"icao":"FAOR"}}},"track":[{"latitude":52.3,"longitude":4.7},{"latitude":999,"longitude":0},{"latitude":-26.1,"longitude":28.2}]}}}}}"#
        default:
            body = #"{"result":{"response":{"data":{"flight":{"track":[]}}}}}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct FlightImportTests {
    private func makeService() -> (FlightTrackerService, URLSession) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PlaybackProtocol.self]
        let session = URLSession(configuration: config)
        return (FlightTrackerService(session: session), session)
    }

    @Test @MainActor
    func playbackCanBeImportedWithoutClosingOverlayHost() async throws {
        let (service, session) = makeService()
        defer { session.invalidateAndCancel() }
        let result = try await service.fetchTrackCoordinates(from: URL(string: "https://api.flightradar24.com/valid")!)
        #expect(result.originICAO == "EHAM")
        #expect(result.destICAO == "FAOR")
        #expect(result.coordinates.count == 2)
        let state = AppState()
        state.isAutoImportPresented = true
        state.applyImportedFlight(originICAO: result.originICAO, destICAO: result.destICAO, coordinates: result.coordinates)
        state.isAutoImportPresented = false
        #expect(state.originAirport?.id == "EHAM")
        #expect(state.destinationAirport?.id == "FAOR")
        #expect(!state.isAutoImportPresented)
        #expect(state.keypointCoordinates.allSatisfy(CLLocationCoordinate2DIsValid))
    }

    @Test
    func emptyPlaybackIsAnError() async {
        let (service, session) = makeService()
        defer { session.invalidateAndCancel() }
        do {
            _ = try await service.fetchTrackCoordinates(from: URL(string: "https://api.flightradar24.com/empty")!)
            Issue.record("Empty playback must not be accepted as an imported track")
        } catch {
            #expect((error as? URLError)?.code == .cannotParseResponse)
        }
    }

    @Test
    func malformedKMLIsRejected() {
        for input in ["<html>Access denied</html>", "<gx:coord>0 999 0</gx:coord><gx:coord>181 0 0</gx:coord>", "<gx:coord>1 2 0</gx:coord>"] {
            #expect(throws: URLError.self) { try FlightTrackerService.parseKMLCoordinates(from: input) }
        }
    }
}
