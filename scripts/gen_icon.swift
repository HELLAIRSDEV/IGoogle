import AppKit
import CoreGraphics

let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

let margin: CGFloat = 56
let rect = CGRect(x: margin, y: margin, width: CGFloat(S) - 2*margin, height: CGFloat(S) - 2*margin)
let bgPath = CGPath(roundedRect: rect, cornerWidth: 190, cornerHeight: 190, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1),
    CGColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: margin, y: CGFloat(S)-margin),
                       end: CGPoint(x: CGFloat(S)-margin, y: margin), options: [])
ctx.restoreGState()

let c = CGPoint(x: 512, y: 512)
let r: CGFloat = 280
let lw: CGFloat = 92
ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(lw)
let silver = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 1),
    CGColor(red: 0.87, green: 0.90, blue: 0.94, alpha: 1),
    CGColor(red: 0.55, green: 0.60, blue: 0.67, alpha: 1)] as CFArray, locations: [0, 0.5, 1])!

func silverClip(_ path: CGPath, start: CGPoint, end: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.replacePathWithStrokedPath(); ctx.clip()
    ctx.drawLinearGradient(silver, start: start, end: end, options: [])
    ctx.restoreGState()
}

// дуга ~270° (разрыв справа по центру)
let a45 = 45.0 * Double.pi / 180.0
let a315 = 315.0 * Double.pi / 180.0
let arc = CGMutablePath()
arc.addArc(center: c, radius: r, startAngle: CGFloat(a45), endAngle: CGFloat(a315), clockwise: false)
silverClip(arc, start: CGPoint(x: c.x - 210, y: c.y + r), end: CGPoint(x: c.x + r, y: c.y - r))

// перекладина: от правого края к центру
let bar = CGMutablePath()
bar.move(to: CGPoint(x: c.x + r, y: c.y))
bar.addLine(to: CGPoint(x: c.x - 10, y: c.y))
silverClip(bar, start: CGPoint(x: c.x, y: c.y), end: CGPoint(x: c.x + r, y: c.y))

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/AppIcon_1024.png"))
print("ok")
