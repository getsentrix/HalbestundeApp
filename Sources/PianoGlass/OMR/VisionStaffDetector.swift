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
        
        // 2. Group peaks into individual 5-line staves with consistent spacing
        var detectedStaves: [[CGFloat]] = []
        var idx = 0
        while idx + 4 < staffPeakIndices.count {
            let candidateLines = Array(staffPeakIndices[idx..<(idx + 5)])
            let spacing = averageSpacing(candidateLines)
            
            var consistent = true
            for j in 0..<4 {
                let gap = abs(candidateLines[j + 1] - candidateLines[j])
                if abs(gap - spacing) > spacing * 0.35 || gap < 4.0 || gap > CGFloat(height) / 8.0 {
                    consistent = false
                    break
                }
            }
            
            if consistent {
                detectedStaves.append(candidateLines)
                idx += 5
            } else {
                idx += 1
            }
        }
        
        #if DEBUG
        print("[VisionStaffDetector] Found \(detectedStaves.count) valid 5-line staves from \(staffPeakIndices.count) peaks.")
        #endif
        
        guard !detectedStaves.isEmpty else { return [] }
        
        // 3. Group 5-line staves into Grand Staff pairs (Treble + Bass) or single staff systems
        var systems = [DetectedStaffSystem]()
        var systemIndex = 0
        var s = 0
        
        while s < detectedStaves.count {
            let trebleLines = detectedStaves[s]
            let trebleSpacing = averageSpacing(trebleLines)
            
            // Check if next staff is a bass staff forming a grand staff pair
            if s + 1 < detectedStaves.count {
                let nextLines = detectedStaves[s + 1]
                let nextSpacing = averageSpacing(nextLines)
                let interStaffGap = nextLines[0] - trebleLines[4]
                
                // Typical grand staff gap is between 1.0x and 7.0x staff spacing
                if interStaffGap >= trebleSpacing * 1.0 && interStaffGap <= trebleSpacing * 7.0 {
                    let avgSpacing = (trebleSpacing + nextSpacing) / 2.0
                    let topY = trebleLines[0]
                    let bottomY = nextLines[4]
                    
                    let barlines = detectBarlines(
                        in: cgImage,
                        topY: topY,
                        bottomY: bottomY,
                        width: width
                    )
                    
                    let systemBounds = CGRect(
                        x: 0,
                        y: max(0, topY - avgSpacing * 2.5),
                        width: CGFloat(width),
                        height: min(CGFloat(height), (bottomY - topY) + avgSpacing * 5.0)
                    )
                    
                    systems.append(DetectedStaffSystem(
                        systemIndex: systemIndex,
                        trebleStaffLines: trebleLines,
                        bassStaffLines: nextLines,
                        staffLineSpacing: avgSpacing,
                        barlineXPositions: barlines,
                        bounds: systemBounds
                    ))
                    systemIndex += 1
                    s += 2
                    continue
                }
            }
            
            // Single staff system (melody, lead sheet, or isolated staff)
            let topY = trebleLines[0]
            let bottomY = trebleLines[4]
            let barlines = detectBarlines(
                in: cgImage,
                topY: topY,
                bottomY: bottomY,
                width: width
            )
            
            let systemBounds = CGRect(
                x: 0,
                y: max(0, topY - trebleSpacing * 2.5),
                width: CGFloat(width),
                height: min(CGFloat(height), (bottomY - topY) + trebleSpacing * 5.0)
            )
            
            systems.append(DetectedStaffSystem(
                systemIndex: systemIndex,
                trebleStaffLines: trebleLines,
                bassStaffLines: [],
                staffLineSpacing: trebleSpacing,
                barlineXPositions: barlines,
                bounds: systemBounds
            ))
            systemIndex += 1
            s += 1
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
        
        // Scan central 70% of columns to avoid margins, table background, and shadows
        let startX = max(0, width * 15 / 100)
        let endX = min(width, width * 85 / 100)
        let colStep = max(2, width / 400)
        
        // Step 1: Sample luminance to determine adaptive ink-vs-paper threshold
        var minLum: Float = 255.0
        var maxLum: Float = 0.0
        var sampledLums = [Float]()
        
        for y in stride(from: height / 6, to: height * 5 / 6, by: max(4, height / 80)) {
            for x in stride(from: startX, to: endX, by: colStep * 4) {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = Float(rawData[offset])
                let g = Float(rawData[offset + 1])
                let b = Float(rawData[offset + 2])
                let lum = (0.299 * r) + (0.587 * g) + (0.114 * b)
                sampledLums.append(lum)
                if lum < minLum { minLum = lum }
                if lum > maxLum { maxLum = lum }
            }
        }
        
        // Adaptive threshold: robust to dim/warm lighting, shadows, and contrast variations
        let contrast = maxLum - minLum
        let inkThreshold: Float
        if contrast > 30.0 && !sampledLums.isEmpty {
            sampledLums.sort()
            let p15 = sampledLums[sampledLums.count * 15 / 100]
            let p85 = sampledLums[sampledLums.count * 85 / 100]
            inkThreshold = p15 + (p85 - p15) * 0.45
        } else {
            inkThreshold = 140.0
        }
        
        // Step 2: Build horizontal ink density profile
        for y in 0..<height {
            var darkPixelCount: Float = 0
            for x in stride(from: startX, to: endX, by: colStep) {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = Float(rawData[offset])
                let g = Float(rawData[offset + 1])
                let b = Float(rawData[offset + 2])
                let luminance = (0.299 * r) + (0.587 * g) + (0.114 * b)
                if luminance < inkThreshold {
                    darkPixelCount += 1.0
                }
            }
            profile[y] = darkPixelCount
        }
        return profile
    }
    
    private func findStaffPeaks(in profile: [Float], height: Int) -> [CGFloat] {
        guard !profile.isEmpty else { return [] }
        var sorted = profile
        sorted.sort()
        let medianVal = sorted[sorted.count / 2]
        let maxVal = sorted.last ?? 1.0
        
        // Threshold: must rise above median background by at least 25% of peak prominence
        let threshold = medianVal + max(1.0, (maxVal - medianVal) * 0.25)
        
        // First pass: collect all local maxima above threshold
        var rawPeaks = [CGFloat]()
        for y in 1..<(height - 1) {
            let val = profile[y]
            if val > threshold && val >= profile[y - 1] && val >= profile[y + 1] {
                rawPeaks.append(CGFloat(y))
            }
        }
        
        // Second pass: cluster adjacent peaks (caused by thick staff lines) into single peaks
        var peaks = [CGFloat]()
        var i = 0
        while i < rawPeaks.count {
            var cluster = [rawPeaks[i]]
            while i + 1 < rawPeaks.count && rawPeaks[i + 1] - rawPeaks[i] <= 4.0 {
                i += 1
                cluster.append(rawPeaks[i])
            }
            let best = cluster.max(by: { profile[Int($0)] < profile[Int($1)] }) ?? cluster[0]
            
            if let lastPeak = peaks.last, (best - lastPeak) < 6.0 {
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
}
