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
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 4)

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
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            Divider()

            // 1. Unified AIRAC Navdata Import
            VStack(alignment: .leading, spacing: 10) {
                Text("AIRAC Navigation Data (One-Click Import)")
                    .font(.subheadline)
                    .fontWeight(.bold)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import AIRAC Cycle Folder")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Select your AIRAC cycle folder (e.g. data/2606). Scans all airports and 5-letter waypoints automatically.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Select Folder...") {
                        selectAIRACFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))

                Text("Data is cached to: ~/Library/Caches/KikiNavMap/NavData/")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Divider()

            // 2. Flight Plan & Map Options
            VStack(alignment: .leading, spacing: 12) {
                Text("Route & Map Options")
                    .font(.subheadline)
                    .fontWeight(.bold)

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

            Divider()

            // 3. Cache Management
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clear All Cache")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red)
                    Text("Clears imported airports, 5-letter waypoints, and cached data.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Clear All Cache") {
                    showClearAlert = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
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
        .padding(20)
        .frame(width: 480)
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
