import SwiftUI

public struct LiquidGlassToolbar: View {
    @ObservedObject var appState: AppState = .shared
    @State private var hasCopied: Bool = false

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            // Origin Airport Field
            AirportSearchField(
                title: "DEP ICAO",
                iconColor: .blue,
                text: $appState.originInputText,
                selectedAirport: appState.originAirport,
                onSelect: { airport in
                    appState.selectOrigin(airport)
                }
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            // Destination Airport Field
            AirportSearchField(
                title: "DEST ICAO",
                iconColor: .orange,
                text: $appState.destinationInputText,
                selectedAirport: appState.destinationAirport,
                onSelect: { airport in
                    appState.selectDestination(airport)
                }
            )

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)

            // Auto Flight Import Button
            Button(action: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    appState.isAutoImportPresented = true
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "airplane.circle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Auto Flight")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .nativeGlassButton(shape: .roundedRectangle(radius: 12))
            .help("Import real-world flight by flight number & date")

            // Copy Route Button
            Button(action: copyRoute) {
                HStack(spacing: 5) {
                    Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                    Text(hasCopied ? "Copied!" : "Copy Route")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .nativeGlassButton(shape: .roundedRectangle(radius: 12))

            // Clear Button
            Button(action: { appState.clearRoute() }) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(6)
            }
            .nativeGlassButton(shape: .circle)
            .foregroundColor(.red)
            .help("Clear Hand-drawn Route")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
    }

    private func copyRoute() {
        appState.copyRouteToClipboard()
        withAnimation {
            hasCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation {
                hasCopied = false
            }
        }
    }
}

public struct RoutePreviewBar: View {
    @ObservedObject var appState: AppState = .shared

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            Text("ROUTE:")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(.cyan)

            if appState.routePoints.isEmpty {
                Text("(Draw line on map to snap 5-letter fixes)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text(appState.routeString)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .liquidGlass(in: Capsule(style: .continuous), interactive: false)
    }
}
