import SwiftUI

public struct MainView: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var navData: NavDataManager = .shared

    public init() {}

    public var body: some View {
        ZStack {
            // 1. Edge-to-Edge Map View
            MapContainerView()
                .ignoresSafeArea()

            // 2. Floating Top Toolbar
            VStack {
                LiquidGlassGroup(spacing: 12) {
                    LiquidGlassToolbar()
                }
                .padding(.top, 14)
                Spacer()
            }

            // 3. Floating Bottom Controls & Indicators
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Spacer()

                    // Bottom Route Preview Pill
                    LiquidGlassGroup(spacing: 8) {
                        RoutePreviewBar()
                    }
                    .padding(.bottom, 14)

                    Spacer()
                }
            }

            // 4. Floating Bottom-Right Buttons (About & Settings)
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Spacer()

                    LiquidGlassGroup(spacing: 8) {
                        // About Button
                        Button(action: { appState.isAboutPresented = true }) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(10)
                        }
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                        .buttonStyle(.plain)
                        .help("About KikiNavMap")

                        // Settings Button
                        Button(action: { appState.isSettingsPresented = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(10)
                        }
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                        .buttonStyle(.plain)
                        .help("Settings & AIRAC Import")
                    }
                    .padding(.trailing, 16)
                }
                .padding(.bottom, 14)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $appState.isSettingsPresented) {
            SettingsSheet()
        }
        .sheet(isPresented: $appState.isAboutPresented) {
            AboutSheet()
        }
        .task {
            await navData.loadData()
        }
    }
}
