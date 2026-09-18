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

            // 4. Floating Bottom-Right Button (Settings)
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Spacer()

                    Button(action: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            appState.isSettingsPresented = true
                        }
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(8)
                    }
                    .nativeGlassButton(shape: .circle)
                    .help("Settings & AIRAC Import")
                    .padding(.trailing, 16)
                }
                .padding(.bottom, 14)
            }

            // 5. In-Window Floating Modal Dialogs (Native Liquid Glass Overlays - No AppKit Sheet Borders)
            if appState.isSettingsPresented || appState.isAboutPresented || appState.isAutoImportPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            appState.isSettingsPresented = false
                            appState.isAboutPresented = false
                            appState.isAutoImportPresented = false
                        }
                    }

                if appState.isSettingsPresented {
                    SettingsSheet()
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                        .zIndex(100)
                }

                if appState.isAboutPresented {
                    AboutSheet()
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                        .zIndex(100)
                }

                if appState.isAutoImportPresented {
                    AutoFlightImportSheet()
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                        .zIndex(100)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: appState.isSettingsPresented)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: appState.isAboutPresented)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: appState.isAutoImportPresented)
        .onKeyPress(.escape) {
            if appState.isSettingsPresented || appState.isAboutPresented || appState.isAutoImportPresented {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    appState.isSettingsPresented = false
                    appState.isAboutPresented = false
                    appState.isAutoImportPresented = false
                }
                return .handled
            }
            return .ignored
        }
        .task {
            await navData.loadData()
        }
    }
}
