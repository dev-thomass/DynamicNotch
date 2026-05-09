#!/usr/bin/env swift
//
//  GenerateAppIcon.swift
//  DynamicNotch
//
//  Programmatically renders the DynamicNotch app icon at all macOS sizes.
//  Run from the repo root:
//      swift Tools/GenerateAppIcon.swift
//
//  Output: DynamicNotch/Assets.xcassets/AppIcon.appiconset/icon-*.png
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Output configuration

let outputDir = "DynamicNotch/Assets.xcassets/AppIcon.appiconset"

// (filename, pixel size)
let exports: [(String, CGFloat)] = [
    ("icon-16.png",      16),
    ("icon-16@2x.png",   32),
    ("icon-32.png",      32),
    ("icon-32@2x.png",   64),
    ("icon-128.png",    128),
    ("icon-128@2x.png", 256),
    ("icon-256.png",    256),
    ("icon-256@2x.png", 512),
    ("icon-512.png",    512),
    ("icon-512@2x.png", 1024),
]

// MARK: - Geometry helpers

/// Apple superellipse (true squircle) used by macOS Big Sur+ icons.
/// `n` ≈ 5 matches Apple's continuous corner curvature.
func squirclePath(rect: CGRect, n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let cx = rect.midX
    let cy = rect.midY
    let a = rect.width / 2
    let b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let cosT = cos(t)
        let sinT = sin(t)
        let x = cx + copysign(pow(abs(cosT), 2 / n), cosT) * a
        let y = cy + copysign(pow(abs(sinT), 2 / n), sinT) * b
        if i == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

/// Notch silhouette: rounded pill body with concave outer corners
/// (the signature shape of macOS notches).
func notchPath(center: CGPoint, width: CGFloat, height: CGFloat, corner: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let left = center.x - width / 2
    let right = center.x + width / 2
    let top = center.y + height / 2
    let bottom = center.y - height / 2

    // Start at top-left of the notch (where it meets the screen edge)
    path.move(to: CGPoint(x: left - corner, y: top))

    // Outer concave corner (top-left)
    path.addCurve(
        to: CGPoint(x: left, y: top - corner),
        control1: CGPoint(x: left - corner * 0.45, y: top),
        control2: CGPoint(x: left, y: top - corner * 0.55)
    )

    // Left side down
    path.addLine(to: CGPoint(x: left, y: bottom + corner))

    // Inner bottom-left rounded corner
    path.addArc(
        center: CGPoint(x: left + corner, y: bottom + corner),
        radius: corner,
        startAngle: .pi,
        endAngle: .pi / 2,
        clockwise: true
    )

    // Bottom edge
    path.addLine(to: CGPoint(x: right - corner, y: bottom))

    // Inner bottom-right rounded corner
    path.addArc(
        center: CGPoint(x: right - corner, y: bottom + corner),
        radius: corner,
        startAngle: .pi / 2,
        endAngle: 0,
        clockwise: true
    )

    // Right side up
    path.addLine(to: CGPoint(x: right, y: top - corner))

    // Outer concave corner (top-right)
    path.addCurve(
        to: CGPoint(x: right + corner, y: top),
        control1: CGPoint(x: right, y: top - corner * 0.55),
        control2: CGPoint(x: right + corner * 0.45, y: top)
    )

    path.closeSubpath()
    return path
}

/// Classic teardrop: circular bottom + tapered top.
func teardropPath(center: CGPoint, width: CGFloat, height: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let radius = width / 2
    let bottomY = center.y - height / 2 + radius
    let tipY = center.y + height / 2

    path.move(to: CGPoint(x: center.x, y: tipY))

    // Right side: from tip to right of circle
    path.addCurve(
        to: CGPoint(x: center.x + radius, y: bottomY),
        control1: CGPoint(x: center.x + radius * 0.55, y: tipY - height * 0.15),
        control2: CGPoint(x: center.x + radius, y: bottomY + radius * 0.85)
    )

    // Bottom semi-circle
    path.addArc(
        center: CGPoint(x: center.x, y: bottomY),
        radius: radius,
        startAngle: 0,
        endAngle: .pi,
        clockwise: true
    )

    // Left side: from left of circle back to tip
    path.addCurve(
        to: CGPoint(x: center.x, y: tipY),
        control1: CGPoint(x: center.x - radius, y: bottomY + radius * 0.85),
        control2: CGPoint(x: center.x - radius * 0.55, y: tipY - height * 0.15)
    )

    path.closeSubpath()
    return path
}

// MARK: - Color helpers

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

// MARK: - Render

/// Renders one icon at the requested pixel size using a 1024-unit reference canvas.
func renderIcon(pixelSize: CGFloat) -> CGImage {
    let canvas: CGFloat = 1024
    let bytesPerRow = 4 * Int(pixelSize)
    guard let ctx = CGContext(
        data: nil,
        width: Int(pixelSize),
        height: Int(pixelSize),
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Could not create CGContext at size \(pixelSize)") }

    // Use 1024 reference coordinates regardless of output size.
    let scale = pixelSize / canvas
    ctx.scaleBy(x: scale, y: scale)

    // High quality rendering
    ctx.setShouldAntialias(true)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas)

    // Slight inset so the squircle sits comfortably (matches Apple's icon grid)
    let padding: CGFloat = 50
    let iconRect = bounds.insetBy(dx: padding, dy: padding)

    let squircle = squirclePath(rect: iconRect)

    // ------------------------------------------------------------------
    // 1. Drop shadow under the icon (subtle, like macOS app icons)
    // ------------------------------------------------------------------
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -12),
        blur: 28,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35)
    )
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // ------------------------------------------------------------------
    // 2. Background gradient inside the squircle
    // ------------------------------------------------------------------
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Vertical gradient, midnight indigo → near-black
    let bgColors = [
        rgb(0x22, 0x22, 0x38),
        rgb(0x10, 0x10, 0x1B),
        rgb(0x06, 0x06, 0x0E),
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.55, 1.0]
    if let bgGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: bgColors,
        locations: bgLocations
    ) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
            end: CGPoint(x: iconRect.midX, y: iconRect.minY),
            options: []
        )
    }

    // 2b. Soft top-center radial highlight (atmosphere)
    let halo = [
        rgb(0xFF, 0xFF, 0xFF, 0.10),
        rgb(0xFF, 0xFF, 0xFF, 0.0),
    ] as CFArray
    if let haloGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: halo,
        locations: [0, 1]
    ) {
        ctx.drawRadialGradient(
            haloGradient,
            startCenter: CGPoint(x: iconRect.midX, y: iconRect.maxY - iconRect.height * 0.20),
            startRadius: 0,
            endCenter: CGPoint(x: iconRect.midX, y: iconRect.maxY - iconRect.height * 0.20),
            endRadius: iconRect.width * 0.55,
            options: []
        )
    }

    ctx.restoreGState()

    // ------------------------------------------------------------------
    // 3. The drop — luminous teardrop (the hero element)
    // ------------------------------------------------------------------
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    let dropWidth: CGFloat = 360
    let dropHeight: CGFloat = 470
    let dropCenter = CGPoint(
        x: iconRect.midX,
        y: iconRect.midY + 10 // slightly above geometric center for optical balance
    )
    let drop = teardropPath(center: dropCenter, width: dropWidth, height: dropHeight)

    // 3a. Soft contact shadow beneath the drop (hint of contact with the surface)
    ctx.saveGState()
    let shadowEllipse = CGRect(
        x: dropCenter.x - dropWidth * 0.45,
        y: dropCenter.y - dropHeight / 2 - 10,
        width: dropWidth * 0.9,
        height: 38
    )
    ctx.setShadow(
        offset: .zero,
        blur: 24,
        color: rgb(0, 0, 0, 0.55)
    )
    ctx.setFillColor(rgb(0, 0, 0, 0.45))
    ctx.fillEllipse(in: shadowEllipse)
    ctx.restoreGState()

    // 3b. Outer cyan glow halo (two passes for richer falloff)
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: 100,
        color: rgb(0x4F, 0xB8, 0xFF, 0.45)
    )
    ctx.addPath(drop)
    ctx.setFillColor(rgb(0xFF, 0xFF, 0xFF, 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: 40,
        color: rgb(0x9E, 0xDB, 0xFF, 0.65)
    )
    ctx.addPath(drop)
    ctx.setFillColor(rgb(0xFF, 0xFF, 0xFF, 1))
    ctx.fillPath()
    ctx.restoreGState()

    // 3c. Drop fill: vertical white → ice blue (richer palette)
    ctx.saveGState()
    ctx.addPath(drop)
    ctx.clip()
    let dropColors = [
        rgb(0xFF, 0xFF, 0xFF),
        rgb(0xEC, 0xF6, 0xFF),
        rgb(0xC4, 0xE2, 0xFF),
        rgb(0x7AB6FF >> 16 & 0xFF, 0x7AB6FF >> 8 & 0xFF, 0x7AB6FF & 0xFF),
    ] as CFArray
    if let dropGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: dropColors,
        locations: [0, 0.35, 0.78, 1]
    ) {
        ctx.drawLinearGradient(
            dropGradient,
            start: CGPoint(x: dropCenter.x, y: dropCenter.y + dropHeight / 2),
            end: CGPoint(x: dropCenter.x, y: dropCenter.y - dropHeight / 2),
            options: []
        )
    }

    // 3d. Inner specular highlight — top-left of the drop body (the wet shine)
    let highlightCenter = CGPoint(
        x: dropCenter.x - dropWidth * 0.20,
        y: dropCenter.y + dropHeight * 0.05
    )
    let highlightColors = [
        rgb(0xFF, 0xFF, 0xFF, 0.95),
        rgb(0xFF, 0xFF, 0xFF, 0.0),
    ] as CFArray
    if let highlightGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: highlightColors,
        locations: [0, 1]
    ) {
        ctx.drawRadialGradient(
            highlightGradient,
            startCenter: highlightCenter,
            startRadius: 0,
            endCenter: highlightCenter,
            endRadius: dropWidth * 0.42,
            options: []
        )
    }

    // 3e. Tip catch-light (white pinpoint near the top tip — adds liquidity)
    let tipHL = CGPoint(x: dropCenter.x, y: dropCenter.y + dropHeight * 0.42)
    let tipColors = [
        rgb(0xFF, 0xFF, 0xFF, 1),
        rgb(0xFF, 0xFF, 0xFF, 0),
    ] as CFArray
    if let tipGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: tipColors,
        locations: [0, 1]
    ) {
        ctx.drawRadialGradient(
            tipGradient,
            startCenter: tipHL,
            startRadius: 0,
            endCenter: tipHL,
            endRadius: dropWidth * 0.18,
            options: []
        )
    }

    // 3f. Bottom volumetric shading
    let shadeColors = [
        rgb(0x00, 0x00, 0x00, 0.0),
        rgb(0x16, 0x36, 0x68, 0.40),
    ] as CFArray
    if let shadeGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: shadeColors,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            shadeGradient,
            start: CGPoint(x: dropCenter.x, y: dropCenter.y),
            end: CGPoint(x: dropCenter.x, y: dropCenter.y - dropHeight / 2),
            options: []
        )
    }
    ctx.restoreGState()

    ctx.restoreGState()

    // ------------------------------------------------------------------
    // 5. Inner rim light on the squircle (top edge), gives a polished feel
    // ------------------------------------------------------------------
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Thin 2.5px white inner stroke that fades down via mask gradient
    ctx.saveGState()
    let rimColors = [
        rgb(0xFF, 0xFF, 0xFF, 0.22),
        rgb(0xFF, 0xFF, 0xFF, 0.0),
    ] as CFArray
    if let rimGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: rimColors,
        locations: [0, 1]
    ) {
        // Draw a thin band along the top inner edge by stroking the squircle inset
        ctx.setLineWidth(3)
        ctx.addPath(squircle)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(
            rimGradient,
            start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
            end: CGPoint(x: iconRect.midX, y: iconRect.midY),
            options: []
        )
    }
    ctx.restoreGState()

    ctx.restoreGState()

    return ctx.makeImage()!
}

// MARK: - Save PNG

func savePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GenerateAppIcon", code: 1)
    }
    try data.write(to: url)
}

// MARK: - Main

let cwd = FileManager.default.currentDirectoryPath
let outURL = URL(fileURLWithPath: cwd).appendingPathComponent(outputDir)
print("Output dir: \(outURL.path)")

guard FileManager.default.fileExists(atPath: outURL.path) else {
    fputs("Error: \(outURL.path) does not exist. Run from the repo root.\n", stderr)
    exit(1)
}

for (filename, pixelSize) in exports {
    let image = renderIcon(pixelSize: pixelSize)
    let dest = outURL.appendingPathComponent(filename)
    do {
        try savePNG(image, to: dest)
        print("✓ wrote \(filename) (\(Int(pixelSize))×\(Int(pixelSize)))")
    } catch {
        fputs("✗ failed to write \(filename): \(error)\n", stderr)
        exit(1)
    }
}

print("\nDone — \(exports.count) icons generated.")
