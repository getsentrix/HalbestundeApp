//
//  LiquidGlassTheme.swift
//  HalbestundeApp
//
//  Color palette, gradients, and visual style tokens for Liquid Glass aesthetic.
//

import SwiftUI

public enum LiquidGlassTheme {
    // MARK: - Dark Ambient Backgrounds
    public static let midnightBackground = Color(red: 0.03, green: 0.04, blue: 0.06) // #080B10
    public static let deepSlate = Color(red: 0.07, green: 0.09, blue: 0.13)
    public static let obsidianSurface = Color(red: 0.10, green: 0.12, blue: 0.17)
    
    // MARK: - Glowing Hand Highlights
    public static let leftHandCyan = Color(red: 0.0, green: 0.90, blue: 1.0)     // #00E5FF
    public static let rightHandAmber = Color(red: 1.0, green: 0.70, blue: 0.0)   // #FFB300
    public static let dualHandViolet = Color(red: 0.83, green: 0.0, blue: 0.98)  // #D500F9
    public static let emeraldGreen = Color(red: 0.0, green: 0.90, blue: 0.46)    // #00E676
    public static let scarletRed = Color(red: 1.0, green: 0.20, blue: 0.30)
    
    // MARK: - Translucent Glass Colors
    public static let glassWhiteOverlay = Color.white.opacity(0.08)
    public static let glassHighlightOverlay = Color.white.opacity(0.18)
    public static let glassDarkOverlay = Color.black.opacity(0.35)
    
    // MARK: - Specular Rim Gradients
    public static var specularRimGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.55),
                Color.white.opacity(0.15),
                Color.white.opacity(0.02),
                Color.white.opacity(0.20)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    public static var cyanRimGradient: LinearGradient {
        LinearGradient(
            colors: [
                leftHandCyan.opacity(0.8),
                leftHandCyan.opacity(0.2),
                Color.clear,
                leftHandCyan.opacity(0.4)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    public static var amberRimGradient: LinearGradient {
        LinearGradient(
            colors: [
                rightHandAmber.opacity(0.8),
                rightHandAmber.opacity(0.2),
                Color.clear,
                rightHandAmber.opacity(0.4)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    public static var iridescentGradient: LinearGradient {
        LinearGradient(
            colors: [
                leftHandCyan.opacity(0.7),
                dualHandViolet.opacity(0.6),
                rightHandAmber.opacity(0.7)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Ambient Backdrop Gradients
    public static var ambientConcertBackdrop: some View {
        ZStack {
            midnightBackground.ignoresSafeArea()
            
            // Atmospheric subtle light orbs
            GeometryReader { proxy in
                Circle()
                    .fill(leftHandCyan.opacity(0.12))
                    .blur(radius: 120)
                    .frame(width: proxy.size.width * 0.8, height: proxy.size.width * 0.8)
                    .offset(x: -proxy.size.width * 0.2, y: -proxy.size.height * 0.1)
                
                Circle()
                    .fill(rightHandAmber.opacity(0.09))
                    .blur(radius: 140)
                    .frame(width: proxy.size.width * 0.9, height: proxy.size.width * 0.9)
                    .offset(x: proxy.size.width * 0.3, y: proxy.size.height * 0.3)
                
                Circle()
                    .fill(dualHandViolet.opacity(0.07))
                    .blur(radius: 110)
                    .frame(width: proxy.size.width * 0.6, height: proxy.size.width * 0.6)
                    .offset(x: proxy.size.width * 0.1, y: proxy.size.height * 0.7)
            }
            .ignoresSafeArea()
        }
    }
}
