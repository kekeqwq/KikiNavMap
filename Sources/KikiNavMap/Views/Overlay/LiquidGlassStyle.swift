import SwiftUI

public struct LiquidGlassModifier<S: Shape>: ViewModifier {
    var shape: S
    var interactive: Bool
    var tint: Color?

    public init(shape: S, interactive: Bool = true, tint: Color? = nil) {
        self.shape = shape
        self.interactive = interactive
        self.tint = tint
    }

    public func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let baseGlass = interactive ? Glass.regular.interactive() : Glass.regular
            let finalGlass = tint != nil ? baseGlass.tint(tint) : baseGlass
            content
                .glassEffect(finalGlass, in: shape)
        } else {
            content
                .background(
                    shape
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
                )
                .overlay(
                    shape
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

public struct LiquidGlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: () -> Content

    public init(spacing: CGFloat? = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

public extension View {
    /// Applies native macOS 27 Liquid Glass effect with continuous refraction, interactive feedback,
    /// and fallback to ultraThinMaterial on earlier macOS versions.
    func liquidGlass<S: Shape>(in shape: S, interactive: Bool = true, tint: Color? = nil) -> some View {
        self.modifier(LiquidGlassModifier(shape: shape, interactive: interactive, tint: tint))
    }

    /// Applies macOS 27 native glass button styling when available.
    @ViewBuilder
    func applyGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(.plain)
        }
    }
}
