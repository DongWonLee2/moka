#!/usr/bin/env swift
// 사용: swift scripts/make-app-icon.swift [출력 폴더]

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let macIconCanvas: CGFloat = 1024
let macIconPlate: CGFloat = 824
let plateFraction = macIconPlate / macIconCanvas

let mockupPlate: CGFloat = 64
let mockupCorner: CGFloat = 15
let mockupGlyph: CGFloat = 36
let cornerFraction = mockupCorner / mockupPlate
let glyphFraction = mockupGlyph / mockupPlate

let gradientStops: [(location: CGFloat, hex: UInt32)] = [
    (0.0, 0xb68c78), (0.55, 0xa47864), (1.0, 0x8f6656),
]
let glyphHex: UInt32 = 0xf5e9e1

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        colorSpace: colorSpace,
        components: [
            CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255,
            CGFloat(hex & 0xff) / 255, 1,
        ])!
}

func drawCupInSVGSpace(in context: CGContext) {
    context.setStrokeColor(color(glyphHex))
    context.setFillColor(color(glyphHex))

    context.setLineWidth(1.6)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: 12.6, y: 2.4))
    context.addCurve(
        to: CGPoint(x: 12.0, y: 6.6),
        control1: CGPoint(x: 10.9, y: 3.7), control2: CGPoint(x: 13.7, y: 4.9))
    context.strokePath()

    context.move(to: CGPoint(x: 4.2, y: 9))
    context.addLine(to: CGPoint(x: 19.8, y: 9))
    context.addLine(to: CGPoint(x: 19.8, y: 11.4))
    context.addArc(
        center: CGPoint(x: 12, y: 11.4), radius: 7.8, startAngle: 0, endAngle: .pi, clockwise: false)
    context.closePath()
    context.fillPath()

    context.addPath(
        CGPath(
            roundedRect: CGRect(x: 6.2, y: 20.2, width: 11.6, height: 1.8),
            cornerWidth: 0.9, cornerHeight: 0.9, transform: nil))
    context.fillPath()
}

extension CGContext {
    func flipToTopLeftOrigin(height: CGFloat) {
        translateBy(x: 0, y: height)
        scaleBy(x: 1, y: -1)
    }
}

func renderIcon(pixels: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let side = CGFloat(pixels)
    context.flipToTopLeftOrigin(height: side)

    let plate = side * plateFraction
    let plateRect = CGRect(x: (side - plate) / 2, y: (side - plate) / 2, width: plate, height: plate)
    let corner = plate * cornerFraction
    context.saveGState()
    context.addPath(
        CGPath(roundedRect: plateRect, cornerWidth: corner, cornerHeight: corner, transform: nil))
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace, colors: gradientStops.map { color($0.hex) } as CFArray,
        locations: gradientStops.map(\.location))!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: plateRect.minY), end: CGPoint(x: 0, y: plateRect.maxY),
        options: [])
    context.restoreGState()

    let glyph = plate * glyphFraction
    context.translateBy(x: (side - glyph) / 2, y: (side - glyph) / 2)
    context.scaleBy(x: glyph / 24, y: glyph / 24)
    drawCupInSVGSpace(in: context)

    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("PNG를 쓰지 못했습니다: \(url.path)")
    }
}

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first
        ?? "App/Sources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@\(scale)x"
        let filename = "icon_\(points)x\(points)\(suffix).png"
        writePNG(renderIcon(pixels: points * scale), to: outputDirectory.appendingPathComponent(filename))
        images.append([
            "filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)",
        ])
    }
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(
    withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try (json + Data("\n".utf8)).write(to: outputDirectory.appendingPathComponent("Contents.json"))
