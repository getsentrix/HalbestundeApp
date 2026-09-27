//
//  ContentView.swift
//  HalbestundeApp
//
//  Main container view hosting the liquid glass navigation tab bar,
//  Score Practice Player, Sheet Music Scanner, Repertoire Library, and Settings.
//

import SwiftUI

public struct ContentView: View {
    @State private var selectedTab: Int = 0
    @StateObject private var playerViewModel = ScorePlayerViewModel()
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            TabView(selection: $selectedTab) {
                ScorePlayerView(viewModel: playerViewModel)
                    .tag(0)
                
                ScannerView { scannedScore in
                    playerViewModel.loadScore(scannedScore)
                    withAnimation {
                        selectedTab = 0
                    }
                }
                .tag(1)
                
                SongLibraryView { selectedScore in
                    playerViewModel.loadScore(selectedScore)
                    withAnimation {
                        selectedTab = 0
                    }
                }
                .tag(2)
                
                SettingsView(audioEngine: playerViewModel.audioEngine)
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            
            // Custom Liquid Glass Bottom Floating Tab Bar
            LiquidGlassTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Liquid Glass Tab Bar
private struct LiquidGlassTabBar: View {
    @Binding var selectedTab: Int
    
    private let tabs: [(icon: String, label: String, tag: Int)] = [
        ("pianokeys", "Practice", 0),
        ("camera.viewfinder", "Scan", 1),
        ("music.note.list", "Repertoire", 2),
        ("gearshape.fill", "Settings", 3)
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.tag) { item in
                let isSelected = selectedTab == item.tag
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = item.tag
                    }
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? LiquidGlassTheme.leftHandCyan : .white.opacity(0.6))
                        
                        Text(item.label)
                            .font(.system(size: 10, weight: isSelected ? .bold : .regular, design: .rounded))
                            .foregroundColor(isSelected ? LiquidGlassTheme.leftHandCyan : .white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        isSelected ?
                            Capsule().fill(LiquidGlassTheme.leftHandCyan.opacity(0.15)) :
                            Capsule().fill(Color.clear)
                    )
                    .glowing(color: LiquidGlassTheme.leftHandCyan, radius: 8, active: isSelected)
                }
                .buttonStyle(SpringPressStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .liquidGlass(
            cornerRadius: 28,
            tintColor: LiquidGlassTheme.midnightBackground.opacity(0.85),
            borderGradient: LiquidGlassTheme.specularRimGradient,
            shadowRadius: 16
        )
    }
}
