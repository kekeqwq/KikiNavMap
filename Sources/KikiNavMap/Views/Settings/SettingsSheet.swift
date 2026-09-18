import SwiftUI
import AppKit

public struct SettingsSheet: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var navData: NavDataManager = .shared
    @Environment(\.dismiss) private var dismiss

    @State private var showClearAlert = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("KikiNavMap Settings")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        appState.isSettingsPresented = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .padding(5)
                }
                .nativeGlassButton(shape: .circle)
            }
            .padding(.bottom, 2)

            // Status Banner
            HStack(spacing: 8) {
                Circle()
                    .fill(navData.isLoaded ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(navData.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if navData.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(10)
            .liquidGlassCard(cornerRadius: 12)

            Divider()
                .opacity(0.4)

            // 1. Unified AIRAC Navdata Import
            VStack(alignment: .leading, spacing: 8) {
                Text("AIRAC Navigation Data (One-Click Import)")
                    .font(.subheadline)
                    .fontWeight(.bold)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import AIRAC Cycle Folder")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Select your AIRAC cycle folder (e.g. data/2606). Scans all airports and waypoints automatically.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { selectAIRACFolder() }) {
                        Text("Select Folder...")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                    .nativeGlassButton(shape: .roundedRectangle(radius: 12))
                }
                .padding(10)
                .liquidGlassCard(cornerRadius: 12)

                Text("Data is cached to: ~/Library/Caches/KikiNavMap/NavData/")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }

            Divider()
                .opacity(0.4)

            // 2. Flight Plan & Map Options
            VStack(alignment: .leading, spacing: 10) {
                Text("Route & Map Options")
                    .font(.subheadline)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Include Airport ICAO in Copied Route", isOn: $appState.includeAirportInCopy)
                        .font(.system(size: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Hand-Draw Snapping Radius:")
                                .font(.system(size: 12))
                            Spacer()
                            Text("\(Int(appState.snappingRadiusNM)) nm")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.accentColor)
                        }
                        Slider(value: $appState.snappingRadiusNM, in: 15...120, step: 5)
                            .onChange(of: appState.snappingRadiusNM) { _, newValue in
                                appState.snappingEngine.snappingRadiusNauticalMiles = newValue
                            }
                    }

                    Toggle("Enhanced Country Borders (Apple Maps Style)", isOn: $appState.showCountryBorders)
                        .font(.system(size: 12))
                }
                .padding(12)
                .liquidGlassCard(cornerRadius: 12)
            }

            Divider()
                .opacity(0.4)

            // 3. Cache Management
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clear All Cache")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red)
                    Text("Clears imported airports, waypoints, and cached data.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { showClearAlert = true }) {
                    Text("Clear All Cache")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .nativeGlassButton(shape: .roundedRectangle(radius: 12))
                .foregroundColor(.red)
            }
            .padding(10)
            .liquidGlassCard(cornerRadius: 12)
            .confirmationDialog(
                "Are you sure you want to clear all cache?",
                isPresented: $showClearAlert,
                titleVisibility: .visible
            ) {
                Button("Clear Everything", role: .destructive) {
                    navData.clearAllCache()
                    appState.clearAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all cached airports and waypoints from ~/Library/Caches/KikiNavMap.")
            }
        }
        .padding(24)
        .frame(width: 500)
        .liquidGlassModalPanel(cornerRadius: 24)
    }

    private func selectAIRACFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select AIRAC Cycle Folder (e.g. data/2606)"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await navData.scanAndCache(from: url)
            }
        }
    }
}
