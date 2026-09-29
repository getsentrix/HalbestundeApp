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

public struct StaffStripSegment: Sendable {
    public let x: CGFloat
    public let lines: [CGFloat] // 5 vertical Y positions (top to bottom: line 0 = top line, line 4 = bottom line)
    
    public init(x: CGFloat, lines: [CGFloat]) {
        self.x = x
        self.lines = lines
    }
}

public struct DetectedStaffSystem {
    public let systemIndex: Int
    public let trebleStaffLines: [CGFloat] // 5 vertical Y positions (top to bottom: line 0 = top line, line 4 = bottom line)
    public let bassStaffLines: [CGFloat]   // 5 vertical Y positions (top to bottom: line 0 = top line, line 4 = bottom line)
    public let staffLineSpacing: CGFloat
    public let barlineXPositions: [CGFloat]
    public let bounds: CGRect
    public let alignedImage: CGImage?
    public let trebleSegments: [StaffStripSegment]
    public let bassSegments: [StaffStripSegment]
    
    public init(
        systemIndex: Int,
        trebleStaffLines: [CGFloat],
        bassStaffLines: [CGFloat],
        staffLineSpacing: CGFloat,
        barlineXPositions: [CGFloat],
        bounds: CGRect,
        alignedImage: CGImage? = nil,
        trebleSegments: [StaffStripSegment] = [],
        bassSegments: [StaffStripSegment] = []
    ) {
        self.systemIndex = systemIndex
        self.trebleStaffLines = trebleStaffLines
        self.bassStaffLines = bassStaffLines
        self.staffLineSpacing = staffLineSpacing
        self.barlineXPositions = barlineXPositions
        self.bounds = bounds
        self.alignedImage = alignedImage
        self.trebleSegments = trebleSegments
        self.bassSegments = bassSegments
    }
    
    /// Interpolates local treble staff line Y position at coordinate X to handle page curvature or sag.
    public func trebleLineY(lineIndex: Int, at x: CGFloat) -> CGFloat {
        guard lineIndex >= 0 && lineIndex < trebleStaffLines.count else { return trebleStaffLines.first ?? 0 }
        return interpolateLineY(segments: trebleSegments, lineIndex: lineIndex, fallback: trebleStaffLines[lineIndex], at: x)
    }
    
    /// Interpolates local bass staff line Y position at coordinate X to handle page curvature or sag.
    public func bassLineY(lineIndex: Int, at x: CGFloat) -> CGFloat {
        guard lineIndex >= 0 && lineIndex < bassStaffLines.count else { return bassStaffLines.first ?? 0 }
        return interpolateLineY(segments: bassSegments, lineIndex: lineIndex, fallback: bassStaffLines[lineIndex], at: x)
    }
    
    private func interpolateLineY(segments: [StaffStripSegment], lineIndex: Int, fallback: CGFloat, at x: CGFloat) -> CGFloat {
        guard segments.count >= 2 else {
            if let single = segments.first, lineIndex < single.lines.count {
                return single.lines[lineIndex]
            }
            return fallback
        }
        if x <= segments[0].x {
            return segments[0].lines[lineIndex]
        }
        if x >= segments[segments.count - 1].x {
            return segments[segments.count - 1].lines[lineIndex]
        }
        for i in 0..<(segments.count - 1) {
            let s0 = segments[i]
            let s1 = segments[i + 1]
            if x >= s0.x && x <= s1.x {
                let span = max(1.0, s1.x - s0.x)
                let t = (x - s0.x) / span
                return s0.lines[lineIndex] + t * (s1.lines[lineIndex] - s0.lines[lineIndex])
            }
        }
        return fallback
    }
}

public final class VisionStaffDetector {
    public init() {}
    
    /// Automatically measures staff line tilt between -20.0° and +20.0° and rotates the CGImage to 0.0°
    public static func deskewCGImage(_ cgImage: CGImage) -> (deskewed: CGImage, angle: CGFloat) {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 100 && height > 100 else { return (cgImage, 0.0) }
        
        let thumbScale = min(1.0, 600.0 / CGFloat(max(width, height)))
        let tw = max(50, Int(CGFloat(width) * thumbScale))
        let th = max(50, Int(CGFloat(height) * thumbScale))
        
        var rawThumb = [UInt8](repeating: 255, count: tw * th)
        guard let thumbCtx = CGContext(
            data: &rawThumb,
            width: tw,
            height: th,
            bitsPerComponent: 8,
            bytesPerRow: tw,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return (cgImage, 0.0) }
        
        thumbCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let thumbCG = thumbCtx.makeImage() else { return (cgImage, 0.0) }
        
        func varianceAtAngle(_ deg: CGFloat) -> CGFloat {
            var rotData = [UInt8](repeating: 255, count: tw * th)
            guard let rotCtx = CGContext(
                data: &rotData,
                width: tw,
                height: th,
                bitsPerComponent: 8,
                bytesPerRow: tw,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return 0.0 }
            
            rotCtx.setFillColor(gray: 1.0, alpha: 1.0)
            rotCtx.fill(CGRect(x: 0, y: 0, width: tw, height: th))
            
            let rad = deg * .pi / 180.0
            rotCtx.translateBy(x: CGFloat(tw) / 2.0, y: CGFloat(th) / 2.0)
            rotCtx.rotate(by: rad)
            rotCtx.translateBy(x: -CGFloat(tw) / 2.0, y: -CGFloat(th) / 2.0)
            rotCtx.draw(thumbCG, in: CGRect(x: 0, y: 0, width: tw, height: th))
            
            let xStart = tw * 15 / 100
            let xEnd = tw * 85 / 100
            var rowSums = [CGFloat](repeating: 0.0, count: th)
            var totalSum: CGFloat = 0.0
            
            for y in 0..<th {
                var rowDark: CGFloat = 0.0
                let rowOffset = y * tw
                for x in xStart..<xEnd {
                    if rotData[rowOffset + x] < 160 {
                        rowDark += 1.0
                    }
                }
                rowSums[y] = rowDark
                totalSum += rowDark
            }
            
            let mean = totalSum / CGFloat(th)
            var varSum: CGFloat = 0.0
            for r in rowSums {
                let diff = r - mean
                varSum += diff * diff
            }
            return varSum / CGFloat(th)
        }
        
        let baseVar = varianceAtAngle(0.0)
        var bestAngle: CGFloat = 0.0
        var maxVar = baseVar
        
        // Coarse pass: -20.0° to +20.0° in 1.0° steps for handheld phone captures
        var testAngle: CGFloat = -20.0
        while testAngle <= 20.05 {
            if abs(testAngle) > 0.1 {
                let v = varianceAtAngle(testAngle)
                if v > maxVar {
                    maxVar = v
                    bestAngle = testAngle
                }
            }
            testAngle += 1.0
        }
        
        // Fine pass: around best angle in 0.1° steps
        if abs(bestAngle) >= 0.3 {
            var fineAngle = bestAngle - 1.0
            while fineAngle <= bestAngle + 1.05 {
                let v = varianceAtAngle(fineAngle)
                if v > maxVar {
                    maxVar = v
                    bestAngle = fineAngle
                }
                fineAngle += 0.1
            }
        }
        
        guard abs(bestAngle) >= 0.2 && maxVar > baseVar * 1.02 else {
            return (cgImage, 0.0)
        }
        
        guard let fullCtx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (cgImage, 0.0) }
        
        fullCtx.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        fullCtx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        let rad = bestAngle * .pi / 180.0
        fullCtx.translateBy(x: CGFloat(width) / 2.0, y: CGFloat(height) / 2.0)
        fullCtx.rotate(by: rad)
        fullCtx.translateBy(x: -CGFloat(width) / 2.0, y: -CGFloat(height) / 2.0)
        fullCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        if let rotated = fullCtx.makeImage() {
            #if DEBUG
            print("[VisionStaffDetector] Deskewed CGImage by \(String(format: "%.2f", bestAngle))°")
            #endif
            return (rotated, bestAngle)
        }
        return (cgImage, 0.0)
    }
    
    /// Analyzes an input image to locate musical staves and measure boundaries
    public func detectStaves(in cgImage: CGImage) async -> [DetectedStaffSystem] {
        let (alignedImage, _) = VisionStaffDetector.deskewCGImage(cgImage)
        let width = alignedImage.width
        let height = alignedImage.height
        guard width > 50 && height > 50 else { return [] }
        
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
        ) else { return [] }
        context.draw(alignedImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // 1. Strip-based vertical slicing (12 vertical columns) to track curved/sagged staves
        let numStrips = 12
        let stripWidth = width / numStrips
        var stripStaves: [[(midX: CGFloat, lines: [CGFloat], spacing: CGFloat)]] = []
        
        for sIdx in 0..<numStrips {
            let startX = sIdx * stripWidth
            let endX = min(width, (sIdx + 1) * stripWidth)
            guard endX - startX > 10 else {
                stripStaves.append([])
                continue
            }
            let midX = CGFloat(startX + endX) / 2.0
            let profile = calculateStripProfile(
                rawData: rawData,
                bytesPerRow: bytesPerRow,
                bytesPerPixel: bytesPerPixel,
                height: height,
                startX: startX,
                endX: endX
            )
            let peaks = findStaffPeaks(in: profile, height: height)
            let stavesInStrip = groupPeaksIntoStaves(peaks: peaks, height: height)
            stripStaves.append(stavesInStrip.map { (midX: midX, lines: $0.lines, spacing: $0.spacing) })
        }
        
        // 2. Chain staff segments across strips into continuous staff tracks
        struct TrackedStaff {
            var segments: [StaffStripSegment]
            var nominalLines: [CGFloat] {
                guard !segments.isEmpty else { return [] }
                var avgLines = [CGFloat](repeating: 0, count: 5)
                for seg in segments {
                    for i in 0..<5 { avgLines[i] += seg.lines[i] }
                }
                return avgLines.map { $0 / CGFloat(segments.count) }
            }
            var spacing: CGFloat {
                let n = nominalLines
                guard n.count == 5 else { return 10.0 }
                return (n[4] - n[0]) / 4.0
            }
        }
        
        var trackedStaves: [TrackedStaff] = []
        for sIdx in 0..<numStrips {
            let candidates = stripStaves[sIdx]
            for cand in candidates {
                var matchedIdx: Int? = nil
                var minDiff: CGFloat = CGFloat.greatestFiniteMagnitude
                for (tIdx, tracked) in trackedStaves.enumerated() {
                    guard let lastSeg = tracked.segments.last else { continue }
                    let diff = abs(cand.lines[0] - lastSeg.lines[0])
                    let tol = max(8.0, cand.spacing * 0.75)
                    if diff < tol && diff < minDiff {
                        minDiff = diff
                        matchedIdx = tIdx
                    }
                }
                if let m = matchedIdx {
                    trackedStaves[m].segments.append(StaffStripSegment(x: cand.midX, lines: cand.lines))
                } else {
                    trackedStaves.append(TrackedStaff(segments: [StaffStripSegment(x: cand.midX, lines: cand.lines)]))
                }
            }
        }
        
        // Filter out short/spurious tracks: must span at least 3 strips (or 25% of strips)
        let minSegments = max(2, numStrips / 4)
        var validTracked = trackedStaves.filter { $0.segments.count >= minSegments }
        validTracked.sort { ($0.nominalLines.first ?? 0) < ($1.nominalLines.first ?? 0) }
        
        // Fallback: If strip tracking finds no staves (e.g. low-res/dense graphics), use global profile
        var finalStaves: [(lines: [CGFloat], spacing: CGFloat, segments: [StaffStripSegment])] = []
        if !validTracked.isEmpty {
            for t in validTracked {
                finalStaves.append((lines: t.nominalLines, spacing: t.spacing, segments: t.segments))
            }
        } else {
            let globalProfile = calculateHorizontalProfile(for: alignedImage)
            let globalPeaks = findStaffPeaks(in: globalProfile, height: height)
            let grouped = groupPeaksIntoStaves(peaks: globalPeaks, height: height)
            for g in grouped {
                finalStaves.append((lines: g.lines, spacing: g.spacing, segments: []))
            }
        }
        
        guard !finalStaves.isEmpty else { return [] }
        
        #if DEBUG
        print("[VisionStaffDetector] Resolved \(finalStaves.count) valid 5-line staves via strip tracking.")
        #endif
        
        // 3. Group 5-line staves into Grand Staff pairs (Treble + Bass) or single staff systems
        var systems = [DetectedStaffSystem]()
        var systemIndex = 0
        var s = 0
        
        while s < finalStaves.count {
            let trebleStaff = finalStaves[s]
            let trebleLines = trebleStaff.lines
            let trebleSpacing = trebleStaff.spacing
            
            // Check if next staff is a bass staff forming a grand staff pair
            if s + 1 < finalStaves.count {
                let bassStaff = finalStaves[s + 1]
                let bassLines = bassStaff.lines
                let bassSpacing = bassStaff.spacing
                let interStaffGap = bassLines[0] - trebleLines[4]
                
                // Typical grand staff gap is between 1.0x and 9.0x staff spacing
                if interStaffGap >= trebleSpacing * 0.8 && interStaffGap <= trebleSpacing * 9.0 {
                    let avgSpacing = (trebleSpacing + bassSpacing) / 2.0
                    let topY = trebleLines[0]
                    let bottomY = bassLines[4]
                    
                    let barlines = detectBarlines(
                        in: alignedImage,
                        rawData: rawData,
                        bytesPerRow: bytesPerRow,
                        bytesPerPixel: bytesPerPixel,
                        topY: topY,
                        bottomY: bottomY,
                        width: width,
                        isGrandStaff: true,
                        trebleBottomY: trebleLines[4],
                        bassTopY: bassLines[0],
                        spacing: avgSpacing
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
                        bassStaffLines: bassLines,
                        staffLineSpacing: avgSpacing,
                        barlineXPositions: barlines,
                        bounds: systemBounds,
                        alignedImage: alignedImage,
                        trebleSegments: trebleStaff.segments,
                        bassSegments: bassStaff.segments
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
                in: alignedImage,
                rawData: rawData,
                bytesPerRow: bytesPerRow,
                bytesPerPixel: bytesPerPixel,
                topY: topY,
                bottomY: bottomY,
                width: width,
                isGrandStaff: false,
                trebleBottomY: nil,
                bassTopY: nil,
                spacing: trebleSpacing
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
                bounds: systemBounds,
                alignedImage: alignedImage,
                trebleSegments: trebleStaff.segments,
                bassSegments: []
            ))
            systemIndex += 1
            s += 1
        }
        
        return systems
    }
    
    // MARK: - Strip & Global Image Signal Analysis
    
    private func calculateStripProfile(
        rawData: [UInt8],
        bytesPerRow: Int,
        bytesPerPixel: Int,
        height: Int,
        startX: Int,
        endX: Int
    ) -> [Float] {
        var profile = [Float](repeating: 0, count: height)
        let sampleStep = max(1, (endX - startX) / 12)
        
        // Local adaptive thresholding for this strip
        var stripLums = [Float]()
        for y in stride(from: height / 6, to: height * 5 / 6, by: max(4, height / 60)) {
            for x in stride(from: startX, to: endX, by: sampleStep * 2) {
                let off = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = Float(rawData[off])
                let g = Float(rawData[off + 1])
                let b = Float(rawData[off + 2])
                stripLums.append((0.299 * r) + (0.587 * g) + (0.114 * b))
            }
        }
        
        let inkThresh: Float
        if stripLums.count > 10 {
            stripLums.sort()
            let p15 = stripLums[stripLums.count * 15 / 100]
            let p85 = stripLums[stripLums.count * 85 / 100]
            inkThresh = max(60.0, min(190.0, p15 + (p85 - p15) * 0.42))
        } else {
            inkThresh = 145.0
        }
        
        for y in 0..<height {
            var darkCount: Float = 0
            let rOff = y * bytesPerRow
            for x in stride(from: startX, to: endX, by: sampleStep) {
                let off = rOff + (x * bytesPerPixel)
                let r = Float(rawData[off])
                let g = Float(rawData[off + 1])
                let b = Float(rawData[off + 2])
                let lum = (0.299 * r) + (0.587 * g) + (0.114 * b)
                if lum < inkThresh {
                    darkCount += 1.0
                }
            }
            profile[y] = darkCount
        }
        return profile
    }
    
    private func groupPeaksIntoStaves(peaks: [CGFloat], height: Int) -> [(lines: [CGFloat], spacing: CGFloat)] {
        var staves: [(lines: [CGFloat], spacing: CGFloat)] = []
        var idx = 0
        while idx + 4 < peaks.count {
            let cand = Array(peaks[idx..<(idx + 5)])
            let sp = averageSpacing(cand)
            var consistent = true
            for j in 0..<4 {
                let gap = abs(cand[j + 1] - cand[j])
                if abs(gap - sp) > sp * 0.42 || gap < 4.0 || gap > CGFloat(height) / 8.0 {
                    consistent = false
                    break
                }
            }
            if consistent {
                staves.append((lines: cand, spacing: sp))
                idx += 5
            } else {
                idx += 1
            }
        }
        return staves
    }
    
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
        
        let startX = max(0, width * 15 / 100)
        let endX = min(width, width * 85 / 100)
        let colStep = max(2, width / 400)
        
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
        
        let threshold = medianVal + max(0.5, (maxVal - medianVal) * 0.18)
        
        var rawPeaks = [CGFloat]()
        for y in 1..<(height - 1) {
            let val = profile[y]
            if val > threshold && val >= profile[y - 1] && val >= profile[y + 1] {
                rawPeaks.append(CGFloat(y))
            }
        }
        
        var peaks = [CGFloat]()
        var i = 0
        let maxClusterGap = max(4.0, CGFloat(height) / 280.0)
        while i < rawPeaks.count {
            var cluster = [rawPeaks[i]]
            while i + 1 < rawPeaks.count && rawPeaks[i + 1] - rawPeaks[i] <= maxClusterGap {
                i += 1
                cluster.append(rawPeaks[i])
            }
            let best = cluster.max(by: { profile[Int($0)] < profile[Int($1)] }) ?? cluster[0]
            
            if let lastPeak = peaks.last, (best - lastPeak) < max(6.0, maxClusterGap) {
                if profile[Int(best)] > profile[Int(peaks.last!)] {
                    peaks[peaks.count - 1] = best
                }
            } else {
                peaks.append(best)
            }
            i += 1
        }
        
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
    
    // MARK: - Grand-Staff Barline Discrimination
    
    private func detectBarlines(
        in cgImage: CGImage,
        rawData: [UInt8],
        bytesPerRow: Int,
        bytesPerPixel: Int,
        topY: CGFloat,
        bottomY: CGFloat,
        width: Int,
        isGrandStaff: Bool,
        trebleBottomY: CGFloat?,
        bassTopY: CGFloat?,
        spacing: CGFloat
    ) -> [CGFloat] {
        let height = cgImage.height
        let topRow = max(0, Int(topY))
        let botRow = min(height - 1, Int(bottomY))
        let staffRows = botRow - topRow
        guard staffRows > 8 else { return equalBarlines(width: width) }
        
        let darkThreshold: Float = 145.0
        let sp = max(6.0, spacing)
        
        // For grand staff: evaluate treble and bass staff spans separately to filter chord stems
        let trebleTop = topRow
        let trebleBot = trebleBottomY.map { min(botRow, Int($0)) } ?? topRow + Int(sp * 4)
        let bassTop = bassTopY.map { max(topRow, Int($0)) } ?? botRow - Int(sp * 4)
        let bassBot = botRow
        
        let trebleRows = max(1, trebleBot - trebleTop)
        let bassRows = max(1, bassBot - bassTop)
        
        var validCandidates = [CGFloat]()
        let minBarlineGap = max(sp * 5.0, CGFloat(width) * 0.04)
        
        var x = max(Int(sp * 2.0), width * 2 / 100)
        let endX = min(width - Int(sp * 2.0), width * 98 / 100)
        
        while x < endX {
            var darkTotal = 0
            var darkTreble = 0
            var darkBass = 0
            var consecutiveWideRows = 0
            var maxConsecutiveWideRows = 0
            
            for row in topRow...botRow {
                let off = (row * bytesPerRow) + (x * bytesPerPixel)
                let r = Float(rawData[off])
                let g = Float(rawData[off + 1])
                let b = Float(rawData[off + 2])
                let lum = 0.299 * r + 0.587 * g + 0.114 * b
                
                if lum < darkThreshold {
                    darkTotal += 1
                    if row <= trebleBot { darkTreble += 1 }
                    if row >= bassTop { darkBass += 1 }
                    
                    // Check horizontal thickness to distinguish thin barlines from chord stems with attached noteheads.
                    // Noteheads span many consecutive rows (>= 0.45 * sp), while staff line intersections are only 1-2px thick.
                    var horizRun = 1
                    var lx = x - 1
                    while lx >= 0 && lx >= x - Int(sp * 1.5) {
                        let lOff = (row * bytesPerRow) + (lx * bytesPerPixel)
                        let llum = 0.299 * Float(rawData[lOff]) + 0.587 * Float(rawData[lOff + 1]) + 0.114 * Float(rawData[lOff + 2])
                        if llum < darkThreshold { horizRun += 1; lx -= 1 } else { break }
                    }
                    var rx = x + 1
                    while rx < width && rx <= x + Int(sp * 1.5) {
                        let rOff = (row * bytesPerRow) + (rx * bytesPerPixel)
                        let rlum = 0.299 * Float(rawData[rOff]) + 0.587 * Float(rawData[rOff + 1]) + 0.114 * Float(rawData[rOff + 2])
                        if rlum < darkThreshold { horizRun += 1; rx += 1 } else { break }
                    }
                    if CGFloat(horizRun) >= sp * 0.95 {
                        consecutiveWideRows += 1
                        if consecutiveWideRows > maxConsecutiveWideRows {
                            maxConsecutiveWideRows = consecutiveWideRows
                        }
                    } else {
                        consecutiveWideRows = 0
                    }
                } else {
                    consecutiveWideRows = 0
                }
            }
            
            // True noteheads attached to stems span multiple consecutive rows (>= sp * 0.45)
            let hasNoteheadBulge = (CGFloat(maxConsecutiveWideRows) >= sp * 0.45)
            
            let qualifies: Bool
            if hasNoteheadBulge {
                // Chord stems have attached notehead bulges; true barlines do not
                qualifies = false
            } else if isGrandStaff {
                // Grand staff barline must span across BOTH staves
                let trebleFrac = Float(darkTreble) / Float(trebleRows)
                let bassFrac = Float(darkBass) / Float(bassRows)
                qualifies = (trebleFrac >= 0.52 && bassFrac >= 0.52)
            } else {
                let frac = Float(darkTotal) / Float(staffRows)
                qualifies = (frac >= 0.65)
            }
            
            if qualifies {
                var clusterEnd = x
                while clusterEnd + 1 < endX {
                    var cDark = 0
                    for row in stride(from: topRow, through: botRow, by: 2) {
                        let off = (row * bytesPerRow) + ((clusterEnd + 1) * bytesPerPixel)
                        let lum = 0.299 * Float(rawData[off]) + 0.587 * Float(rawData[off + 1]) + 0.114 * Float(rawData[off + 2])
                        if lum < darkThreshold { cDark += 1 }
                    }
                    let cFrac = Float(cDark) / Float((staffRows / 2) + 1)
                    if cFrac >= 0.45 {
                        clusterEnd += 1
                    } else {
                        break
                    }
                }
                let cx = CGFloat(x + clusterEnd) / 2.0
                if validCandidates.isEmpty || (cx - validCandidates.last!) >= minBarlineGap {
                    validCandidates.append(cx)
                }
                x = clusterEnd + 1
            } else {
                x += 1
            }
        }
        
        #if DEBUG
        print("[VisionStaffDetector] detectBarlines: found \(validCandidates.count) verified barlines (grandStaff=\(isGrandStaff)).")
        #endif
        
        if validCandidates.count >= 2 {
            return validCandidates
        }
        
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
