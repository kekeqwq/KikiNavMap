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
    /// Applies native macOS 27 Liquid Glass effect with continuous refraction and interactive feedback
    func liquidGlass<S: Shape>(in shape: S, interactive: Bool = true, tint: Color? = nil) -> some View {
        self.modifier(LiquidGlassModifier(shape: shape, interactive: interactive, tint: tint))
    }

    /// Applies Apple Swift native Liquid Glass button style (.glass or .glassProminent) on macOS 26+
    /// with large rounded corner (radius 12) or circle shape matching the main airport search field.
    @ViewBuilder
    func nativeGlassButton(prominent: Bool = false, shape: ButtonBorderShape = .roundedRectangle(radius: 12)) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(shape)
                    .focusable(false)
                    .focusEffectDisabled()
            } else {
                self
                    .buttonStyle(.glass)
                    .buttonBorderShape(shape)
                    .focusable(false)
                    .focusEffectDisabled()
            }
        } else {
            self
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
        }
    }

    /// Floating modal dialog panel with pure Swift native Liquid Glass and soft natural shadow
    func liquidGlassModalPanel(cornerRadius: CGFloat = 24) -> some View {
        self
            .liquidGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: false)
            .shadow(color: .black.opacity(0.35), radius: 36, x: 0, y: 16)
    }

    /// Native liquid glass card container for grouping content inside panels
    func liquidGlassCard(cornerRadius: CGFloat = 12) -> some View {
        self
            .liquidGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: false)
    }

    /// Native liquid glass input field with glass background
    func liquidGlassInputField(cornerRadius: CGFloat = 8, isFocused: Bool = false) -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: true)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isFocused ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}
