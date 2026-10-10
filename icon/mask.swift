// usage: swift mask.swift <source.png> <out.png>
// Finds the icon tile in source (anything differing from the corner/background colour),
// clips it to a rounded rect and centres it on a transparent 1024x1024 canvas.
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
// threshold halfway between background and the tile fill sampled 1/8 inward, so a soft
// shadow/halo around the tile isn't mistaken for the tile itself
func edge(_ pts: [(Int, Int)]) -> Int? {
    let fill = diff(pts[pts.count / 8].0, pts[pts.count / 8].1)
    let thr = max(4, fill / 2)
    // require a short run so single noisy pixels don't count as an edge
    return pts.indices.first { i in pts[i..<min(i + 3, pts.count)].allSatisfy { diff($0.0, $0.1) > thr } }
}
// tile edges: first differing pixel scanning inward along the middle row/column
let mx = w / 2, my = h / 2
let l = edge((0..<w).map { ($0, my) }) ?? 0
let r = w - 1 - (edge((0..<w).reversed().map { ($0, my) }) ?? 0)
let t = edge((0..<h).map { (mx, $0) }) ?? 0
let b = h - 1 - (edge((0..<h).reversed().map { (mx, $0) }) ?? 0)

// small inset drops the anti-aliased fringe / shadow
let inset = Double(r - l) * 0.004
let tile = CGRect(x: Double(l) + inset, y: Double(h - 1 - b) + inset,
                  width: Double(r - l + 1) - 2 * inset, height: Double(b - t + 1) - 2 * inset)
FileHandle.standardError.write("tile: x \(l)...\(r), y \(t)...\(b) of \(w)x\(h)\n".data(using: .utf8)!)

let size = 1024, tileSize = 824.0, margin = (1024.0 - tileSize) / 2
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high

let dst = CGRect(x: margin, y: margin, width: tileSize, height: tileSize)
ctx.addPath(CGPath(roundedRect: dst, cornerWidth: tileSize * 0.225, cornerHeight: tileSize * 0.225, transform: nil))
ctx.clip()

// scale/translate so the source tile lands exactly on dst
let sx = tileSize / tile.width, sy = tileSize / tile.height
ctx.draw(cg, in: CGRect(x: margin - tile.minX * sx, y: margin - tile.minY * sy,
                        width: Double(w) * sx, height: Double(h) * sy))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
