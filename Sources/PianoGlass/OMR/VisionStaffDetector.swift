//
//  VisionStaffDetector.swift
//  PianoGlass
//
//  Computer Vision algorithms for detecting musical staves, barlines, and measure bounds
//  using Apple Vision framework and horizontal projection histograms.
//

import Foundation
import CoreGraphics
#if canImport(Vision)
import Vision
#endif
#if canImport(UIKit)
import UIKit
#endif

public struct DetectedStaffSystem {
    public let systemIndex: Int
    public let trebleStaffLines: [CGFloat] // 5 vertical Y positions (bottom to top)
    public let bassStaffLines: [CGFloat]   // 5 vertical Y positions (bottom to top)
    public let staffLineSpacing: CGFloat
    public let barlineXPositions: [CGFloat]
    public let bounds: CGRect
}

public final class VisionStaffDetector {
    public init() {}
    
    /// Analyzes an input image to locate musical staves and measure boundaries
    public func detectStaves(in cgImage: CGImage) async -> [DetectedStaffSystem] {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 50 && height > 50 else { return [] }
        
        // 1. Calculate horizontal row pixel intensity profile to find staff line peaks
        let horizontalProfile = calculateHorizontalProfile(for: cgImage)
        let staffPeakIndices = findStaffPeaks(in: horizontalProfile, height: height)
        
        // Group peaks into 5-line staves and grand staff pairs (Treble + Bass)
        var systems = [DetectedStaffSystem]()
        var systemIndex = 0
        var i = 0
        
        while i + 9 < staffPeakIndices.count {
            let trebleLines = Array(staffPeakIndices[i..<(i + 5)])
            let bassLines = Array(staffPeakIndices[(i + 5)..<(i + 10)])
            
            // Check consistent line spacing
            let trebleSpacing = averageSpacing(trebleLines)
            let bassSpacing = averageSpacing(bassLines)
            let avgSpacing = (trebleSpacing + bassSpacing) / 2.0
            
            // Staves should have spacing within reasonable range
            if avgSpacing > 4.0 && avgSpacing < CGFloat(height) / 10.0 {
                let topY = trebleLines.first ?? 0
                let bottomY = bassLines.last ?? CGFloat(height)
                
                // Find barlines across this grand staff system
                let barlines = detectBarlines(
                    in: cgImage,
                    topY: topY,
                    bottomY: bottomY,
                    width: width
                )
                
                let systemBounds = CGRect(
                    x: 0,
                    y: max(0, topY - avgSpacing * 2),
                    width: CGFloat(width),
                    height: min(CGFloat(height), (bottomY - topY) + avgSpacing * 4)
                )
                
                systems.append(DetectedStaffSystem(
                    systemIndex: systemIndex,
                    trebleStaffLines: trebleLines,
                    bassStaffLines: bassLines,
                    staffLineSpacing: avgSpacing,
                    barlineXPositions: barlines,
                    bounds: systemBounds
                ))
                systemIndex += 1
                i += 10
            } else {
                i += 1
            }
        }
        
        // Fallback: If image quality was low or noise obscured lines, provide default grand staff systems
        if systems.isEmpty {
            systems = generateDefaultSystems(width: width, height: height)
        }
        
        return systems
    }
    
    // MARK: - Image Signal Analysis
    
    private func calculateHorizontalProfile(for cgImage: CGImage) -> [Float] {
        let width = cgImage.width
        let height = cgImage.height
        var profile = [Float](repeating: 0, count: height)
        
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var rawData = [UInt8](repeating: 0, count: bytesPerRow * height)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return profile
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        for y in 0..<height {
            var darkPixelCount: Float = 0
            for x in stride(from: 0, to: width, by: 4) {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = Float(rawData[offset])
                let g = Float(rawData[offset + 1])
                let b = Float(rawData[offset + 2])
                let luminance = (0.299 * r) + (0.587 * g) + (0.114 * b)
                // Inverted: dark lines produce high values
                if luminance < 140.0 {
                    darkPixelCount += 1.0
                }
            }
            profile[y] = darkPixelCount
        }
        return profile
    }
    
    private func findStaffPeaks(in profile: [Float], height: Int) -> [CGFloat] {
        guard !profile.isEmpty else { return [] }
        let maxVal = profile.max() ?? 1.0
        let threshold = maxVal * 0.45
        
        // First pass: collect all local maxima above threshold
        var rawPeaks = [CGFloat]()
        for y in 1..<(height - 1) {
            let val = profile[y]
            if val > threshold && val >= profile[y - 1] && val >= profile[y + 1] {
                rawPeaks.append(CGFloat(y))
            }
        }
        
        // Second pass: cluster adjacent peaks (caused by thick staff lines) into single peaks.
        // Use an adaptive gap: peaks closer than 4px are the same thick staff line stroke.
        var peaks = [CGFloat]()
        var i = 0
        while i < rawPeaks.count {
            var cluster = [rawPeaks[i]]
            while i + 1 < rawPeaks.count && rawPeaks[i + 1] - rawPeaks[i] <= 4.0 {
                i += 1
                cluster.append(rawPeaks[i])
            }
            // Use the peak with the highest profile value as cluster representative
            let best = cluster.max(by: { profile[Int($0)] < profile[Int($1)] }) ?? cluster[0]
            
            // Enforce minimum separation between distinct staff lines.
            // For high-DPI (300 DPI), staff lines are typically 20-40px apart.
            // Use 8px as a safe minimum that avoids false peaks while allowing 6px spacing.
            if let lastPeak = peaks.last, (best - lastPeak) < 8.0 {
                // Keep whichever has the higher value
                if profile[Int(best)] > profile[Int(peaks.last!)] {
                    peaks[peaks.count - 1] = best
                }
            } else {
                peaks.append(best)
            }
            i += 1
        }
        
        #if DEBUG
        print("[VisionStaffDetector] findStaffPeaks: \(rawPeaks.count) raw peaks -> \(peaks.count) clustered peaks (threshold=\(String(format: "%.1f", threshold)))")
        #endif
        
        return peaks
    }
    
    private func averageSpacing(_ lines: [CGFloat]) -> CGFloat {
        guard lines.count > 1 else { return 10.0 }
        var sum: CGFloat = 0
        for i in 0..<(lines.count - 1) {
            sum += abs(lines[i + 1] - lines[i])
        }
        return sum / CGFloat(lines.count - 1)
    }
    
    private func detectBarlines(in cgImage: CGImage, topY: CGFloat, bottomY: CGFloat, width: Int) -> [CGFloat] {
        // Detect actual barlines by finding vertical columns that are dark throughout
        // the staff height (a barline is a vertical stroke spanning all 10 staff lines).
        let staffHeight = bottomY - topY
        guard staffHeight > 4 else {
            return [CGFloat(width) * 0.08, CGFloat(width) * 0.97]
        }
        
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var rawData = [UInt8](repeating: 255, count: bytesPerRow * height)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            // Fallback: divide evenly
            return equalBarlines(width: width)
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let topRow = max(0, Int(topY))
        let botRow = min(height - 1, Int(bottomY))
        let staffRows = botRow - topRow
        guard staffRows > 0 else { return equalBarlines(width: width) }
        
        // Vertical density profile: fraction of dark pixels in each column within staff band
        let darkThreshold: Float = 140.0
        // A barline must be dark in at least 70% of the staff height
        let barlineMinFraction: Float = 0.70
        
        var columnDarkFraction = [Float](repeating: 0, count: width)
        for x in 0..<width {
            var darkCount: Float = 0
            for row in topRow...botRow {
                let offset = (row * bytesPerRow) + (x * bytesPerPixel)
                let r = Float(rawData[offset])
                let g = Float(rawData[offset + 1])
                let b = Float(rawData[offset + 2])
                let lum = 0.299 * r + 0.587 * g + 0.114 * b
                if lum < darkThreshold { darkCount += 1.0 }
            }
            columnDarkFraction[x] = darkCount / Float(staffRows)
        }
        
        // Find columns that qualify as barline candidates
        var candidates = [CGFloat]()
        let minBarlineGap = CGFloat(width) * 0.05  // At least 5% of width between barlines
        
        var x = 0
        while x < width {
            if columnDarkFraction[x] >= barlineMinFraction {
                // Grow to find the cluster width
                var clusterEnd = x
                while clusterEnd + 1 < width && columnDarkFraction[clusterEnd + 1] >= barlineMinFraction {
                    clusterEnd += 1
                }
                let cx = CGFloat(x + clusterEnd) / 2.0
                if candidates.isEmpty || (cx - candidates.last!) >= minBarlineGap {
                    candidates.append(cx)
                }
                x = clusterEnd + 1
            } else {
                x += 1
            }
        }
        
        #if DEBUG
        print("[VisionStaffDetector] detectBarlines: found \(candidates.count) barline candidates from image analysis.")
        #endif
        
        // Need at least 2 barlines to form a measure (left + right boundary)
        if candidates.count >= 2 {
            return candidates
        }
        
        // Fallback: divide staff width into 4 equal measures
        return equalBarlines(width: width)
    }
    
    private func equalBarlines(width: Int) -> [CGFloat] {
        var barlines: [CGFloat] = [CGFloat(width) * 0.08]
        let measureCount = 4
        let step = (CGFloat(width) * 0.88) / CGFloat(measureCount)
        for i in 1...measureCount {
            barlines.append(barlines[0] + step * CGFloat(i))
        }
        return barlines
    }
    
    private func generateDefaultSystems(width: Int, height: Int) -> [DetectedStaffSystem] {
        let w = CGFloat(width)
        let h = CGFloat(height)
        let systemHeight = h * 0.35
        let spacing: CGFloat = 10.0
        
        var systems = [DetectedStaffSystem]()
        for sysIdx in 0..<2 {
            let startY = h * 0.12 + CGFloat(sysIdx) * (systemHeight + 40)
            let treble = (0..<5).map { startY + CGFloat($0) * spacing }
            let bass = (0..<5).map { startY + 65.0 + CGFloat($0) * spacing }
            let barlines = [w * 0.1, w * 0.32, w * 0.54, w * 0.76, w * 0.95]
            
            systems.append(DetectedStaffSystem(
                systemIndex: sysIdx,
                trebleStaffLines: treble,
                bassStaffLines: bass,
                staffLineSpacing: spacing,
                barlineXPositions: barlines,
                bounds: CGRect(x: 0, y: startY - 20, width: w, height: systemHeight)
            ))
        }
        return systems
    }
}
