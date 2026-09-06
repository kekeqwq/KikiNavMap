import SwiftUI
import MapKit
import AppKit

public struct MapContainerView: NSViewRepresentable {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var navData: NavDataManager = .shared

    public init() {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> InteractiveMapView {
        let mapView = InteractiveMapView()
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView

        // Apple Maps native vector map styling (automatic light/dark mode)
        mapView.mapType = .standard
        mapView.showsCompass = true
        mapView.showsScale = true

        // Configure initial camera position over Europe / Middle East
        let center = CLLocationCoordinate2D(latitude: 45.0, longitude: 35.0)
        let span = MKCoordinateSpan(latitudeDelta: 35.0, longitudeDelta: 45.0)
        mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)

        // Setup Enhanced Country Borders if enabled
        if appState.showCountryBorders {
            let borders = CountryBorders.shared.polylines
            context.coordinator.borderPolylines = borders
            mapView.addOverlays(borders, level: .aboveRoads)
        }

        return mapView
    }

    public func updateNSView(_ nsView: InteractiveMapView, context: Context) {
        context.coordinator.updateOverlaysAndAnnotations()
    }

    // MARK: - Coordinator
    public final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapContainerView
        weak var mapView: InteractiveMapView?
        var borderPolylines: [MKPolyline] = []

        var currentRoutePolyline: MKPolyline?

        init(_ parent: MapContainerView) {
            self.parent = parent
        }

        public func updateOverlaysAndAnnotations() {
            guard let mapView = mapView else { return }

            // 1. Update Great-Circle Flight Route Polyline
            if let old = currentRoutePolyline {
                mapView.removeOverlay(old)
                currentRoutePolyline = nil
            }

            let greatCircleCoords = parent.appState.greatCirclePathCoordinates
            if greatCircleCoords.count >= 2 {
                let polyline = MKPolyline(coordinates: greatCircleCoords, count: greatCircleCoords.count)
                polyline.title = "Route"
                currentRoutePolyline = polyline
                mapView.addOverlay(polyline, level: .aboveLabels)
            }

            // 2. Update Annotations for Keypoints & Airports
            let existingRouteAnnos = mapView.annotations.filter { $0 is RoutePointAnnotation || $0 is AirportAnnotation }
            mapView.removeAnnotations(existingRouteAnnos)

            if let dep = parent.appState.originAirport {
                let depAnno = AirportAnnotation(airport: dep, isOrigin: true)
                mapView.addAnnotation(depAnno)
            }
            if let dest = parent.appState.destinationAirport {
                let destAnno = AirportAnnotation(airport: dest, isOrigin: false)
                mapView.addAnnotation(destAnno)
            }

            for pt in parent.appState.routePoints {
                let ptAnno = RoutePointAnnotation(point: pt)
                mapView.addAnnotation(ptAnno)
            }
        }

        // MARK: - Overlay Renderer
        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                if polyline.title == "Route" {
                    // Rainbow Gradient Great-Circle Polyline
                    let renderer = MKGradientPolylineRenderer(polyline: polyline)
                    renderer.lineWidth = 5.0
                    let colors: [NSColor] = [
                        NSColor(calibratedRed: 0.0, green: 0.85, blue: 1.0, alpha: 1.0),   // Cyan
                        NSColor(calibratedRed: 0.1, green: 0.5, blue: 0.95, alpha: 1.0),   // Blue
                        NSColor(calibratedRed: 0.0, green: 0.95, blue: 0.45, alpha: 1.0),  // Green
                        NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0),  // Red
                        NSColor(calibratedRed: 0.7, green: 0.3, blue: 0.95, alpha: 1.0)    // Purple
                    ]
                    let locations: [CGFloat] = [0.0, 0.25, 0.5, 0.75, 1.0]
                    renderer.setColors(colors, locations: locations)
                    renderer.lineCap = .round
                    renderer.lineJoin = .round
                    return renderer
                } else if polyline.title == "Drawing" {
                    let renderer = MKPolylineRenderer(polyline: polyline)
                    renderer.strokeColor = NSColor.systemTeal.withAlphaComponent(0.85)
                    renderer.lineWidth = 3.5
                    renderer.lineDashPattern = [6, 6]
                    renderer.lineCap = .round
                    return renderer
                } else {
                    // Country Borders Overlay (Apple Maps matching high-contrast lines)
                    let renderer = MKPolylineRenderer(polyline: polyline)
                    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    if isDark {
                        renderer.strokeColor = NSColor(white: 0.0, alpha: 0.85)
                        renderer.lineWidth = 1.6
                    } else {
                        renderer.strokeColor = NSColor(white: 0.25, alpha: 0.9)
                        renderer.lineWidth = 1.8
                    }
                    return renderer
                }
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        // MARK: - Annotation Views
        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let aptAnno = annotation as? AirportAnnotation {
                let id = "AirportPinView"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                if view == nil {
                    view = MKAnnotationView(annotation: aptAnno, reuseIdentifier: id)
                }
                view?.annotation = aptAnno
                view?.canShowCallout = true

                let pinColor = aptAnno.isOrigin ? NSColor.systemSky : NSColor.systemAmber
                view?.image = createAirportBadgeImage(code: aptAnno.airport.id, color: pinColor, isOrigin: aptAnno.isOrigin)
                view?.centerOffset = CGPoint(x: 0, y: -12)
                return view
            }

            if let ptAnno = annotation as? RoutePointAnnotation {
                let id = "RoutePointView"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                if view == nil {
                    view = MKAnnotationView(annotation: ptAnno, reuseIdentifier: id)
                    view?.isDraggable = true
                }
                view?.annotation = ptAnno
                view?.canShowCallout = true
                view?.image = createWaypointBadgeImage(ident: ptAnno.point.ident, isCoord: ptAnno.point.isCoordinate)
                view?.centerOffset = CGPoint(x: 0, y: 0)
                return view
            }

            return nil
        }

        public func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            if newState == .ending, let ptAnno = view.annotation as? RoutePointAnnotation {
                parent.appState.updatePointPosition(id: ptAnno.point.id, newCoordinate: ptAnno.coordinate)
            }
        }

        private func createAirportBadgeImage(code: String, color: NSColor, isOrigin: Bool) -> NSImage {
            let size = CGSize(width: 54, height: 32)
            let img = NSImage(size: size)
            img.lockFocus()

            // Pin Head
            let headRect = CGRect(x: (size.width - 16) / 2, y: 14, width: 16, height: 16)
            color.setFill()
            NSBezierPath(ovalIn: headRect).fill()

            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: (size.width - 6) / 2, y: 19, width: 6, height: 6)).fill()

            // Needle
            color.setStroke()
            let needle = NSBezierPath()
            needle.move(to: CGPoint(x: size.width / 2, y: 14))
            needle.line(to: CGPoint(x: size.width / 2, y: 10))
            needle.lineWidth = 2.5
            needle.stroke()

            // Label pill
            let pillRect = CGRect(x: 2, y: 0, width: size.width - 4, height: 13)
            NSColor(white: 0.1, alpha: 0.85).setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: 3, yRadius: 3).fill()

            let font = NSFont.boldSystemFont(ofSize: 9)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white
            ]
            let str = NSAttributedString(string: code, attributes: attrs)
            let strSize = str.size()
            str.draw(at: CGPoint(x: (size.width - strSize.width) / 2, y: 0.5))

            img.unlockFocus()
            return img
        }

        private func createWaypointBadgeImage(ident: String, isCoord: Bool) -> NSImage {
            let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
            let tag = "[\(ident)]"
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: isCoord ? NSColor.systemYellow : NSColor.systemCyan
            ]
            let str = NSAttributedString(string: tag, attributes: textAttrs)
            let textSize = str.size()
            let size = CGSize(width: textSize.width + 20, height: 20)

            let img = NSImage(size: size)
            img.lockFocus()

            // Handle Ring
            let circleColor = isCoord ? NSColor.systemYellow : NSColor.white
            circleColor.setFill()
            NSBezierPath(ovalIn: CGRect(x: 2, y: 5, width: 10, height: 10)).fill()

            let innerColor = isCoord ? NSColor.systemOrange : NSColor.systemBlue
            innerColor.setFill()
            NSBezierPath(ovalIn: CGRect(x: 4.5, y: 7.5, width: 5, height: 5)).fill()

            // Label background
            NSColor(white: 0.05, alpha: 0.8).setFill()
            let bgRect = CGRect(x: 14, y: 2, width: textSize.width + 6, height: textSize.height + 2)
            NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3).fill()

            str.draw(at: CGPoint(x: 17, y: 2.5))

            img.unlockFocus()
            return img
        }
    }
}

// MARK: - Interactive Map View Subclass
public final class InteractiveMapView: MKMapView {
    private var rawScreenPoints: [CGPoint] = []
    private var isShiftMode = false
    private var shiftStartPoint: CGPoint = .zero
    private var drawingPolyline: MKPolyline?

    override public init(frame: CGRect) {
        super.init(frame: frame)
        disableDragZoomGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        disableDragZoomGestures()
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        disableDragZoomGestures()
    }

    private func disableDragZoomGestures() {
        for g in gestureRecognizers {
            let name = String(describing: type(of: g))
            if name.contains("OneHanded") || name.contains("Zoom") {
                g.isEnabled = false
            }
        }
    }

    override public func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        let isShift = event.modifierFlags.contains(.shift)
        for g in gestureRecognizers {
            let name = String(describing: type(of: g))
            if name.contains("Pan") || name.contains("DirectTouch") {
                g.isEnabled = !isShift
            }
        }
    }

    // MARK: - Mouse Events (Shift = Hand-draw or Point-Click, Normal = Map Pan)
    override public func mouseDown(with event: NSEvent) {
        // If user clicked directly on an annotation, pass to super
        let hit = hitTest(event.locationInWindow)
        if let _ = hit as? MKAnnotationView {
            super.mouseDown(with: event)
            return
        }

        if event.modifierFlags.contains(.shift) {
            // Shift mode active: start drawing or click detection
            isShiftMode = true
            for g in gestureRecognizers {
                let name = String(describing: type(of: g))
                if name.contains("Pan") || name.contains("DirectTouch") {
                    g.isEnabled = false
                }
            }
            let pt = convert(event.locationInWindow, from: nil)
            shiftStartPoint = pt
            rawScreenPoints = [pt]
            // Do NOT call super.mouseDown so map does not pan
            return
        }

        // Normal click: allows normal map panning & navigation
        isShiftMode = false
        super.mouseDown(with: event)
    }

    override public func mouseDragged(with event: NSEvent) {
        if isShiftMode {
            // Hand-drawing freehand stroke
            let pt = convert(event.locationInWindow, from: nil)
            rawScreenPoints.append(pt)

            // Update live dashed drawing line on map
            let coords = rawScreenPoints.map { convert($0, toCoordinateFrom: self) }
            if coords.count >= 2 {
                if let old = drawingPolyline {
                    removeOverlay(old)
                }
                let poly = MKPolyline(coordinates: coords, count: coords.count)
                poly.title = "Drawing"
                drawingPolyline = poly
                addOverlay(poly, level: .aboveLabels)
            }
            return
        }

        // Normal drag: pans map smoothly!
        super.mouseDragged(with: event)
    }

    override public func mouseUp(with event: NSEvent) {
        if isShiftMode {
            isShiftMode = false
            for g in gestureRecognizers {
                let name = String(describing: type(of: g))
                if name.contains("Pan") || name.contains("DirectTouch") {
                    g.isEnabled = true
                }
            }
            if let old = drawingPolyline {
                removeOverlay(old)
                drawingPolyline = nil
            }

            let endPt = convert(event.locationInWindow, from: nil)
            let distance = hypot(endPt.x - shiftStartPoint.x, endPt.y - shiftStartPoint.y)

            if distance < 6.0 {
                // Shift + Click: Point-and-click mode (single nearest 5-letter fix)
                let coord = convert(endPt, toCoordinateFrom: self)
                AppState.shared.handleShiftPointClick(coord)
            } else {
                // Shift + Drag: Continuous hand-drawing stroke
                let coords = rawScreenPoints.map { convert($0, toCoordinateFrom: self) }
                if coords.count >= 2 {
                    AppState.shared.handleFinishedStroke(coords)
                }
            }

            rawScreenPoints.removeAll()
            return
        }

        super.mouseUp(with: event)
    }

    // MARK: - Right Click Context Menu (Insert Coordinate Fix or Delete Waypoint)
    override public func rightMouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let coord = convert(pt, toCoordinateFrom: self)
        let coordCode = CoordinateFix.format(latitude: coord.latitude, longitude: coord.longitude)

        let menu = NSMenu(title: "MapOptions")

        // If clicked on or near an existing route waypoint, offer to delete it
        let nearbyWaypoint = AppState.shared.routePoints.first { wpt in
            let d = SpatialKDTree.distanceMeters(lat1: coord.latitude, lon1: coord.longitude, lat2: wpt.latitude, lon2: wpt.longitude)
            return d < 25000.0 // ~13.5 nm
        }

        if let wpt = nearbyWaypoint {
            let delItem = NSMenuItem(
                title: "Delete Waypoint [\(wpt.ident)]",
                action: #selector(didSelectDeleteWaypoint(_:)),
                keyEquivalent: ""
            )
            delItem.representedObject = wpt.id.uuidString
            menu.addItem(delItem)
            menu.addItem(NSMenuItem.separator())
        }

        let item = NSMenuItem(
            title: "Insert Coordinate Fix [\(coordCode)]",
            action: #selector(didSelectInsertCoordinate(_:)),
            keyEquivalent: ""
        )
        item.representedObject = NSValue(point: NSPoint(x: coord.latitude, y: coord.longitude))
        menu.addItem(item)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func didSelectDeleteWaypoint(_ sender: NSMenuItem) {
        if let uuidStr = sender.representedObject as? String, let uuid = UUID(uuidString: uuidStr) {
            AppState.shared.removeRoutePoint(id: uuid)
        }
    }

    @objc private func didSelectInsertCoordinate(_ sender: NSMenuItem) {
        if let val = sender.representedObject as? NSValue {
            let pt = val.pointValue
            let coord = CLLocationCoordinate2D(latitude: pt.x, longitude: pt.y)
            AppState.shared.insertCoordinate(at: coord)
        }
    }
}

// MARK: - Custom Annotations
public final class AirportAnnotation: NSObject, MKAnnotation {
    public let airport: Airport
    public let isOrigin: Bool
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude)
    }
    public var title: String? {
        "\(airport.id) (\(isOrigin ? "DEP" : "DEST"))"
    }
    public var subtitle: String? {
        airport.name
    }

    public init(airport: Airport, isOrigin: Bool) {
        self.airport = airport
        self.isOrigin = isOrigin
        super.init()
    }
}

public final class RoutePointAnnotation: NSObject, MKAnnotation {
    public var point: RoutePoint
    public var coordinate: CLLocationCoordinate2D {
        get {
            CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
        set {
            point.latitude = newValue.latitude
            point.longitude = newValue.longitude
        }
    }
    public var title: String? {
        point.ident
    }

    public init(point: RoutePoint) {
        self.point = point
        super.init()
    }
}

private extension NSColor {
    static let systemSky = NSColor(calibratedRed: 0.05, green: 0.6, blue: 0.95, alpha: 1.0)
    static let systemAmber = NSColor(calibratedRed: 0.95, green: 0.6, blue: 0.05, alpha: 1.0)
}
