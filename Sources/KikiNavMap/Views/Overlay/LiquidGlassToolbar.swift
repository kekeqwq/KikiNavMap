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

            // Copy Route Button
            Button(action: copyRoute) {
                HStack(spacing: 4) {
                    Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                    Text(hasCopied ? "Copied!" : "Copy Route")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundColor(hasCopied ? .green : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(hasCopied ? Color.green.opacity(0.15) : Color.blue.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(hasCopied ? Color.green.opacity(0.4) : Color.blue.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Clear Button
            Button(action: { appState.clearRoute() }) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.red)
                    .padding(7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.red.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Clear Hand-drawn Route")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
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
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }
}
