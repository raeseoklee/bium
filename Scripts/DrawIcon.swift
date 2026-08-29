// Draws the bium app icon and writes a 1024x1024 PNG.
//
//   swift Scripts/DrawIcon.swift dist/icon-1024.png
//
// The mark is a disk platter whose lower-right quadrant has been opened up,
// with freed blocks drifting out of the gap: emptying, not cleaning.
import AppKit
import CoreGraphics
import Foundation

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/icon-1024.png"
let side = 1024
let scale = CGFloat(side) / 1024

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("could not create the bitmap context") }

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let indigoTop = rgb(63, 81, 181)
let indigoBottom = rgb(38, 50, 130)
let ringColor = rgb(255, 255, 255)
let blockColor = rgb(64, 224, 208)

// Background: a rounded square in the macOS proportion, with a soft vertical
// gradient so the icon does not read as flat at large sizes.
let inset: CGFloat = 96 * scale
let rect = CGRect(x: inset, y: inset, width: CGFloat(side) - inset * 2, height: CGFloat(side) - inset * 2)
let squircle = CGPath(roundedRect: rect, cornerWidth: 200 * scale, cornerHeight: 200 * scale, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
if let gradient = CGGradient(colorsSpace: space, colors: [indigoTop, indigoBottom] as CFArray, locations: [0, 1]) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY),
        options: []
    )
}
ctx.restoreGState()

// Everything from here on is clipped to the background shape, so a mark that
// drifts too far can never bleed past the rounded corner.
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

// The platter ring, open toward the lower right.
let center = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
let radius = 268 * scale
ctx.setStrokeColor(ringColor)
ctx.setLineWidth(84 * scale)
ctx.setLineCap(.round)
ctx.addArc(
    center: center, radius: radius,
    startAngle: -10 * .pi / 180, endAngle: 260 * .pi / 180,
    clockwise: false
)
ctx.strokePath()

// A smaller inner ring, cut on the same side, so the mark keeps a sense of
// depth without needing shading.
ctx.setLineWidth(40 * scale)
ctx.setStrokeColor(ringColor.copy(alpha: 0.55) ?? ringColor)
ctx.addArc(
    center: center, radius: 132 * scale,
    startAngle: 10 * .pi / 180, endAngle: 250 * .pi / 180,
    clockwise: false
)
ctx.strokePath()

// Freed blocks drifting out through the gap, decreasing in size so the eye
// reads a direction rather than three separate marks.
ctx.setFillColor(blockColor)
let blocks: [(CGFloat, CGFloat, CGFloat)] = [
    (632, 360, 100),
    (748, 268, 70),
    (838, 196, 44),
]
for (x, y, size) in blocks {
    let r = CGRect(x: x * scale, y: y * scale, width: size * scale, height: size * scale)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: size * 0.30 * scale, cornerHeight: size * 0.30 * scale, transform: nil))
    ctx.fillPath()
}

ctx.restoreGState()

guard let image = ctx.makeImage() else { fatalError("could not render the icon") }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("could not encode the PNG") }
try FileManager.default.createDirectory(
    atPath: (output as NSString).deletingLastPathComponent,
    withIntermediateDirectories: true
)
try data.write(to: URL(fileURLWithPath: output))
print("완성: \(output)")
