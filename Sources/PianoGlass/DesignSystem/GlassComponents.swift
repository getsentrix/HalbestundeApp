//
//  GlassComponents.swift
//  PianoGlass
//
//  Reusable liquid glass UI components: Cards, Buttons, Badges, and Docks.
//

import SwiftUI

// MARK: - Glass Card Container
public struct GlassCard<Content: View>: View {
    public var cornerRadius: CGFloat
    public var accentColor: Color?
    public var content: () -> Content
    
    public init(
        cornerRadius: CGFloat = 22,
        accentColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
        self.content = content
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(18)
        .liquidGlass(
            cornerRadius: cornerRadius,
            tintColor: accentColor?.opacity(0.08) ?? Color.white.opacity(0.06),
            borderGradient: accentColor != nil ?
                LinearGradient(
                    colors: [accentColor!.opacity(0.7), accentColor!.opacity(0.2), Color.white.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ) : LiquidGlassTheme.specularRimGradient
        )
    }
}

// MARK: - Glass Action Button
public struct GlassButton: View {
    public var title: String
    public var icon: String?
    public var accentColor: Color
    public var isFullWidth: Bool
    public var action: () -> Void
    
    public init(
        title: String,
        icon: String? = nil,
        accentColor: Color = LiquidGlassTheme.leftHandCyan,
        isFullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.accentColor = accentColor
        self.isFullWidth = isFullWidth
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(
                Capsule()
                    .fill(accentColor.opacity(0.25))
                    .background(Capsule().fill(.ultraThinMaterial))
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.4), Color.white.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: accentColor.opacity(0.35), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(SpringPressStyle(glowColor: accentColor))
    }
}

// MARK: - Glass Icon Button
public struct GlassIconButton: View {
    public var icon: String
    public var size: CGFloat
    public var tint: Color
    public var isActive: Bool
    public var action: () -> Void
    
    public init(
        icon: String,
        size: CGFloat = 44,
        tint: Color = .white,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.tint = tint
        self.isActive = isActive
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? tint.opacity(0.28) : Color.white.opacity(0.08))
                    .background(Circle().fill(.ultraThinMaterial))
                
                Circle()
                    .stroke(
                        isActive ?
                            LinearGradient(colors: [tint, tint.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                            LiquidGlassTheme.specularRimGradient,
                        lineWidth: isActive ? 1.5 : 0.8
                    )
                
                Image(systemName: icon)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(isActive ? tint : .white.opacity(0.9))
            }
            .frame(width: size, height: size)
            .modifier(GlowModifier(color: tint, radius: 10, active: isActive))
        }
        .buttonStyle(SpringPressStyle(glowColor: tint))
    }
}

// MARK: - Glass Badge
public struct GlassBadge: View {
    public var text: String
    public var color: Color
    
    public init(text: String, color: Color = LiquidGlassTheme.leftHandCyan) {
        self.text = text
        self.color = color
    }
    
    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
                    .background(Capsule().fill(.ultraThinMaterial))
            )
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.5), lineWidth: 0.8)
            )
    }
}
