import SwiftUI
import AppKit

public struct AboutSheet: View {
    @ObservedObject var navData: NavDataManager = .shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            // Header with top-right Close
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        AppState.shared.isAboutPresented = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .padding(5)
                }
                .nativeGlassButton(shape: .circle)
            }
            .padding(.bottom, -12)

            // App Icon
            if let iconImage = loadAppIcon() {
                Image(nsImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            } else {
                Image(systemName: "airplane.circle.fill")
                    .resizable()
                    .foregroundColor(.accentColor)
                    .frame(width: 80, height: 80)
            }

            // Title & Version
            VStack(spacing: 4) {
                Text("KikiNavMap")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("Version 1.1.0 (macOS 27 Native)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // AIRAC Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(navData.isLoaded ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(navData.statusMessage)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .liquidGlass(in: Capsule(), interactive: false)

            // Description
            Text("Minimalist flight plan creation and airway routing tool for virtual aviators. Built with pure Swift, native Apple Maps rendering, Liquid Glass UI, and high-speed BGL navigation data decoding.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Divider()
                .opacity(0.4)

            // Copyright & License
            VStack(spacing: 3) {
                Text("Copyright © 2026 kekeqwq")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                Text("Released under the GNU General Public License v3.0 (GPL-3.0)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            // GitHub Button & Dismiss
            HStack(spacing: 14) {
                Button(action: {
                    if let url = URL(string: "https://github.com/kekeqwq/KikiNavMap") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .semibold))
                        Text("GitHub")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .nativeGlassButton(shape: .roundedRectangle(radius: 12))

                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        AppState.shared.isAboutPresented = false
                    }
                }) {
                    Text("Close")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                }
                .nativeGlassButton(prominent: false, shape: .roundedRectangle(radius: 12))
            }
            .padding(.top, 4)
        }
        .padding(26)
        .frame(width: 420)
        .liquidGlassModalPanel(cornerRadius: 24)
    }

    private func loadAppIcon() -> NSImage? {
        let paths: [URL?] = [
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
            URL(fileURLWithPath: "Sources/KikiNavMap/Resources/AppIcon.png"),
            URL(fileURLWithPath: "Sources/KikiNavMap/Resources/AppIcon.icns")
        ]
        for case let url? in paths {
            if let img = NSImage(contentsOf: url) {
                return img
            }
        }
        return NSApp.applicationIconImage
    }
}

