// usage: swift mask.swift <source.png> <out.png>
// Finds the artwork in source (anything differing from the corner/background colour) and
// centres it on a rounded-square plate (filled with that background colour, with a soft
// drop shadow) on a transparent 1024x1024 canvas, macOS Big Sur-style like VS Code's icon.
import AppKit

let args = CommandLine.arguments
let src = NSImage(contentsOfFile: args[1])!
var rect = NSRect.zero
let cg = src.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
let w = cg.width, h = cg.height

// render source into a known RGBA buffer (row 0 = top)
var px = [UInt8](repeating: 0, count: w * h * 4)
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
px.withUnsafeMutableBytes { buf in
    let c = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
}

let bg = Array(px[0..<4])
func diff(_ x: Int, _ y: Int) -> Int {
    let i = (y * w + x) * 4
    return (0..<4).map { abs(Int(px[i + $0]) - Int(bg[$0])) }.max()!
}

// bounding box of everything noticeably different from the background
var l = w, r = -1, t = h, b = -1
for y in 0..<h { for x in 0..<w where diff(x, y) > 12 {
    l = min(l, x); r = max(r, x); t = min(t, y); b = max(b, y)
} }
FileHandle.standardError.write("art: x \(l)...\(r), y \(t)...\(b) of \(w)x\(h)\n".data(using: .utf8)!)
let art = CGRect(x: l, y: h - 1 - b, width: r - l + 1, height: b - t + 1)  // CG coords (origin bottom-left)

let size = 1024, tileSize = 824.0, margin = (1024.0 - tileSize) / 2
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high

// plate: rounded square in the source's background colour, with a soft shadow
let plate = CGRect(x: margin, y: margin + 10, width: tileSize, height: tileSize)
let path = CGPath(roundedRect: plate, cornerWidth: tileSize * 0.225, cornerHeight: tileSize * 0.225, transform: nil)
let a = CGFloat(bg[3]) / 255
let fill = CGColor(srgbRed: CGFloat(bg[0]) / 255 / max(a, 0.001), green: CGFloat(bg[1]) / 255 / max(a, 0.001),
                   blue: CGFloat(bg[2]) / 255 / max(a, 0.001), alpha: 1)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
ctx.setFillColor(fill)
ctx.addPath(path)
ctx.fillPath()
ctx.restoreGState()

// artwork: longest side = 70% of the plate, centred, clipped to the plate
ctx.addPath(path)
ctx.clip()
let s = tileSize * 0.70 / Double(max(art.width, art.height))
let ax = plate.midX - art.midX * s, ay = plate.midY - art.midY * s
ctx.draw(cg, in: CGRect(x: ax, y: ay, width: Double(w) * s, height: Double(h) * s))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
