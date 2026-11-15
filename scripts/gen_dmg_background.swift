import SwiftUI
import AppKit

struct DMGBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.14),
                         Color(red: 0.04, green: 0.05, blue: 0.07)],
                startPoint: .top, endPoint: .bottom)

            Circle()
                .fill(Color(red: 0.29, green: 0.52, blue: 0.96).opacity(0.20))
                .frame(width: 420, height: 420).blur(radius: 140)
                .offset(x: -260, y: -140)
            Circle()
                .fill(Color(red: 0.55, green: 0.33, blue: 0.95).opacity(0.16))
                .frame(width: 420, height: 420).blur(radius: 150)
                .offset(x: 260, y: 140)

            Text("G")
                .font(.system(size: 320, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.045))
                .position(x: 450, y: 250)

            Text("IGoogle")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .position(x: 450, y: 62)

            Image(systemName: "arrow.right")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.55)],
                                   startPoint: .leading, endPoint: .trailing))
                .position(x: 450, y: 250)

            Text("Перетащите IGoogle в Applications")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .position(x: 450, y: 434)
        }
        .frame(width: 900, height: 520)
    }
}

@MainActor func renderBG(to path: String) {
    let r = ImageRenderer(content: DMGBackground())
    r.scale = 3
    guard let cg = r.cgImage else { print("fail"); return }
    // Finder трактует пиксели как точки — отдаём ровно размер окна (900×520),
    // но рисуем в 3x и уменьшаем (сглаженно).
    let w = 900, h = 520
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let out = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: out)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    print("ok \(path) \(w)x\(h)")
}

MainActor.assumeIsolated {
    renderBG(to: "/Users/user/Documents/project/IGoogle/macos/Packaging/dmg-background.png")
}
