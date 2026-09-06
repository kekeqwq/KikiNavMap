import SwiftUI
import AppKit

public struct AboutSheet: View {
    @ObservedObject var navData: NavDataManager = .shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            // App Icon
            if let iconImage = loadAppIcon() {
                Image(nsImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
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

                Text("Version 1.0.0 (macOS 27 Native)")
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
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.06)))

            // Description
            Text("Minimalist flight plan creation and airway routing tool for virtual aviators. Built with pure Swift, native Apple Maps rendering, Liquid Glass UI, and high-speed BGL navigation data decoding.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Divider()

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
            HStack(spacing: 12) {
                Button(action: {
                    if let url = URL(string: "https://github.com/kekeqwq/KikiNavMap") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "link")
                            .font(.system(size: 10, weight: .bold))
                        Text("GitHub Repository")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 420)
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

