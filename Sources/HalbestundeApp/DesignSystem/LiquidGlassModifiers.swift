//
//  LiquidGlassModifiers.swift
//  HalbestundeApp
//
//  Custom SwiftUI ViewModifiers implementing the Liquid Glass Design System.
//

import SwiftUI

public struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tintColor: Color
    var borderGradient: LinearGradient
    var shadowRadius: CGFloat
    var shadowColor: Color
    
    public init(
        cornerRadius: CGFloat = 20,
        tintColor: Color = Color.white.opacity(0.06),
        borderGradient: LinearGradient = LiquidGlassTheme.specularRimGradient,
        shadowRadius: CGFloat = 16,
        shadowColor: Color = Color.black.opacity(0.4)
    ) {
        self.cornerRadius = cornerRadius
        self.tintColor = tintColor
        self.borderGradient = borderGradient
        self.shadowRadius = shadowRadius
        self.shadowColor = shadowColor
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tintColor)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                // Specular rim reflection border
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderGradient, lineWidth: 1.2)
            )
            .overlay(
                // Inner top specular highlight for realistic 3D glass edge
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.8
                    )
                    .padding(0.8)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 8)
    }
}

public struct LiquidGlassPillModifier: ViewModifier {
    var tintColor: Color
    var strokeColor: Color
    
    public init(tintColor: Color = Color.white.opacity(0.08), strokeColor: Color = Color.white.opacity(0.2)) {
        self.tintColor = tintColor
        self.strokeColor = strokeColor
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(tintColor)
                    .background(Capsule().fill(.ultraThinMaterial))
            )
            .overlay(
                Capsule()
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
    }
}

public struct GlowModifier: ViewModifier {
    var color: Color
    var radius: CGFloat
    var active: Bool
    
    public func body(content: Content) -> some View {
        if active {
            content
                .shadow(color: color.opacity(0.7), radius: radius * 0.5, x: 0, y: 0)
                .shadow(color: color.opacity(0.4), radius: radius, x: 0, y: 0)
        } else {
            content
        }
    }
}

public struct SpringPressStyle: ButtonStyle {
    public var scaleAmount: CGFloat = 0.94
    public var glowOnPress: Bool = true
    public var glowColor: Color = LiquidGlassTheme.leftHandCyan
    
    public init(scaleAmount: CGFloat = 0.94, glowOnPress: Bool = true, glowColor: Color = LiquidGlassTheme.leftHandCyan) {
        self.scaleAmount = scaleAmount
        self.glowOnPress = glowOnPress
        self.glowColor = glowColor
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .modifier(GlowModifier(color: glowColor, radius: 14, active: configuration.isPressed && glowOnPress))
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - View Extension Helpers
public extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 20,
        tintColor: Color = Color.white.opacity(0.06),
        borderGradient: LinearGradient = LiquidGlassTheme.specularRimGradient,
        shadowRadius: CGFloat = 16,
        shadowColor: Color = Color.black.opacity(0.4)
    ) -> some View {
        self.modifier(
            LiquidGlassModifier(
                cornerRadius: cornerRadius,
                tintColor: tintColor,
                borderGradient: borderGradient,
                shadowRadius: shadowRadius,
                shadowColor: shadowColor
            )
        )
    }
    
    func liquidGlassPill(
        tintColor: Color = Color.white.opacity(0.08),
        strokeColor: Color = Color.white.opacity(0.2)
    ) -> some View {
        self.modifier(LiquidGlassPillModifier(tintColor: tintColor, strokeColor: strokeColor))
    }
    
    func glowing(color: Color, radius: CGFloat = 12, active: Bool = true) -> some View {
        self.modifier(GlowModifier(color: color, radius: radius, active: active))
    }
}
