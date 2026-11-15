import SwiftUI
import AVFoundation
import AppKit
import CoreImage

// ===== Параметры =====
let W = 1080, H = 1920, FPS = 30
let voDur: [Double] = [3.217778, 6.730068, 7.287755, 4.164853, 3.666304, 6.800816]
let lead = 0.55, tail = 0.75, introDur = 1.3, outroDur = 2.0

struct SceneT { let start: Double; let dur: Double; let voStart: Double; let voFile: String }
func timeline() -> (scenes: [SceneT], total: Double) {
    var arr: [SceneT] = []; var t = introDur
    for i in 0..<voDur.count {
        let d = voDur[i] + lead + tail
        arr.append(SceneT(start: t, dur: d, voStart: t + lead, voFile: "/tmp/vo/vo\(i+1).aiff"))
        t += d
    }
    return (arr, t + outroDur)
}
let TL = timeline()

// ===== Палитра =====
let cBG1 = Color(red: 0.12, green: 0.10, blue: 0.22)
let cBG2 = Color(red: 0.04, green: 0.03, blue: 0.09)
let cSilver = Color(red: 0.90, green: 0.92, blue: 0.97)
let cBlue = Color(red: 0.29, green: 0.52, blue: 0.96)
let cPurple = Color(red: 0.55, green: 0.33, blue: 0.95)
let cGreen = Color(red: 0.20, green: 0.80, blue: 0.38)
let cInk = Color(red: 0.09, green: 0.09, blue: 0.13)

func ease(_ x: Double) -> Double { let v = min(max(x, 0), 1); return v * v * (3 - 2 * v) }

// ===== Фон =====
struct Stars: View {
    let t: Double
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 987654321
            func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double((seed >> 33) % 100000) / 100000.0 }
            for _ in 0..<95 {
                let x = rnd() * size.width, y = rnd() * size.height
                let r = 1.2 + rnd() * 2.6
                let tw = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 2.0 + rnd() * 6.28))
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.55 * tw)))
            }
        }
    }
}

struct Bg: View {
    let t: Double
    var body: some View {
        ZStack {
            LinearGradient(colors: [cBG1, cBG2], startPoint: .top, endPoint: .bottom)
            Circle().fill(cPurple.opacity(0.28)).frame(width: 1000, height: 1000).blur(radius: 200).offset(x: -300, y: -420)
            Circle().fill(cBlue.opacity(0.22)).frame(width: 900, height: 900).blur(radius: 200).offset(x: 320, y: 460)
            Stars(t: t)
        }
        .ignoresSafeArea()
    }
}

// ===== Маскот =====
struct Mascot: View {
    var size: CGFloat = 180
    var bob: CGFloat = 0
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.white, cSilver.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .shadow(color: .white.opacity(0.25), radius: 40)
            HStack(spacing: size * 0.20) {
                Circle().fill(cInk).frame(width: size * 0.11, height: size * 0.11)
                Circle().fill(cInk).frame(width: size * 0.11, height: size * 0.11)
            }.offset(y: -size * 0.07)
            Capsule().fill(cInk).frame(width: size * 0.26, height: size * 0.05).offset(y: size * 0.17)
        }
        .offset(y: bob)
    }
}

// ===== Переиспользуемые =====
func titleText(_ s: String, _ size: CGFloat) -> some View {
    Text(s)
        .font(.system(size: size, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
}

func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
    c()
        .padding(28)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 2))
}

// ===== Сцены =====
struct SceneContent: View {
    let index: Int
    let p: Double      // 0..1 внутри сцены
    let t: Double

    private var a: Double { ease(p * 1.4) }
    private var rise: CGFloat { CGFloat((1 - a) * 60) }
    private var fade: Double { min(1, min(p / 0.10, (1 - p) / 0.10)) }

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 120)
            content
            Spacer()
        }
        .padding(.horizontal, 70)
        .opacity(fade)
        .offset(y: rise)
    }

    @ViewBuilder private var content: some View {
        switch index {
        case 0: sceneHook
        case 1: sceneClip
        case 2: sceneShare
        case 3: sceneNotch
        case 4: sceneBackground
        default: sceneCTA
        }
    }

    // 1. Хук
    private var sceneHook: some View {
        VStack(spacing: 40) {
            Mascot(size: 230, bob: CGFloat(sin(t * 3) * 8))
            titleText("Pixel ↔ MacBook", 96)
            Text("наконец-то как одно целое")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(cSilver.opacity(0.85))
        }
    }

    // 2. Буфер
    private var sceneClip: some View {
        VStack(spacing: 34) {
            titleText("Общий буфер", 82)
            card {
                HStack(spacing: 22) {
                    Image(systemName: "doc.on.clipboard.fill").font(.system(size: 54)).foregroundStyle(cBlue)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Привет с Pixel").font(.system(size: 40, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        Text("уже на MacBook").font(.system(size: 28)).foregroundStyle(cSilver.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 54)).foregroundStyle(cGreen)
                        .scaleEffect(a)
                }
            }
            Text("в реальном времени, в обе стороны")
                .font(.system(size: 34, weight: .medium, design: .rounded)).foregroundStyle(cSilver.opacity(0.75))
            Mascot(size: 120, bob: CGFloat(sin(t * 3) * 6))
        }
    }

    // 3. Поделиться / файлы
    private var sceneShare: some View {
        VStack(spacing: 30) {
            titleText("Файлы и фото", 82)
            card {
                VStack(alignment: .leading, spacing: 22) {
                    row("square.and.arrow.up", "Поделиться", cSilver)
                    row("paperplane.fill", "Отправить на MacBook", cBlue)
                    Divider().overlay(.white.opacity(0.15))
                    row("photo.fill", "Фото → сразу в Галерею", cGreen)
                }
            }
            Text("файлы уходят в Downloads, фото — в «Фото»")
                .font(.system(size: 32, weight: .medium, design: .rounded)).foregroundStyle(cSilver.opacity(0.75))
                .multilineTextAlignment(.center)
        }
    }

    private func row(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 20) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(color)
            Text(text).font(.system(size: 38, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Spacer(minLength: 0)
        }
    }

    // 4. Островок под чёлкой
    private var sceneNotch: some View {
        VStack(spacing: 40) {
            titleText("Прямо под чёлкой", 80)
            ZStack(alignment: .top) {
                // имитация верхней кромки экрана
                RoundedRectangle(cornerRadius: 26).fill(Color.black)
                    .frame(width: 900, height: 150)
                // чёлка
                UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18)
                    .fill(Color.black).frame(width: 200, height: 46).offset(y: -2)
                // капсула
                VStack(spacing: 0) {
                    Spacer().frame(height: 46)
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.clipboard.fill").font(.system(size: 22, weight: .semibold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Получен буфер").font(.system(size: 22, weight: .semibold))
                            Text("Привет с MacBook").font(.system(size: 16)).foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 14)
                    .frame(width: 260)
                    .background(BottomRoundedShape(radius: 20).fill(Color.black))
                    .foregroundStyle(.white)
                }
                .frame(width: 260, height: 46 + 76)
            }
            .frame(height: 250)
            Text("Dynamic-Island уведомление на Mac")
                .font(.system(size: 32, weight: .medium, design: .rounded)).foregroundStyle(cSilver.opacity(0.75))
        }
    }

    // 5. Фон / VPN
    private var sceneBackground: some View {
        VStack(spacing: 36) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 150)).foregroundStyle(cGreen)
                .shadow(color: cGreen.opacity(0.5), radius: 40)
            titleText("Работает в фоне", 78)
            Text("держит соединение · не боится VPN")
                .font(.system(size: 36, weight: .medium, design: .rounded)).foregroundStyle(cSilver.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    // 6. CTA
    private var sceneCTA: some View {
        VStack(spacing: 34) {
            ZStack {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(LinearGradient(colors: [.white, cSilver.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 260, height: 260)
                    .shadow(color: .white.opacity(0.3), radius: 50)
                Text("G").font(.system(size: 170, weight: .heavy, design: .rounded)).foregroundStyle(cInk)
            }
            titleText("IGoogle", 110)
            Text("Общий буфер, файлы и фото\nмежду Pixel и MacBook")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(cSilver.opacity(0.9)).multilineTextAlignment(.center)
            Text("APK · DMG · github.com/HELLAIRSDEV/IGoogle")
                .font(.system(size: 30, weight: .medium, design: .monospaced))
                .foregroundStyle(cBlue)
                .padding(.horizontal, 26).padding(.vertical, 16)
                .background(.white.opacity(0.08), in: Capsule())
        }
    }
}

struct BottomRoundedShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct IntroView: View {
    let p: Double
    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(LinearGradient(colors: [.white, cSilver.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 220, height: 220).shadow(color: .white.opacity(0.3), radius: 40)
                Text("G").font(.system(size: 150, weight: .heavy, design: .rounded)).foregroundStyle(cInk)
            }
            .scaleEffect(0.7 + 0.3 * ease(min(p * 2, 1)))
            titleText("IGoogle", 96).opacity(ease(min(p * 2, 1)))
        }
    }
}

struct FrameView: View {
    let t: Double
    var body: some View {
        ZStack {
            Bg(t: t)
            if t < introDur {
                IntroView(p: t / introDur)
            } else if t >= TL.total - outroDur {
                IntroView(p: min(1, (t - (TL.total - outroDur)) / outroDur))
            } else if let (idx, p) = sceneAt(t) {
                SceneContent(index: idx, p: p, t: t)
            }
        }
        .frame(width: CGFloat(W), height: CGFloat(H))
    }
}

func sceneAt(_ t: Double) -> (Int, Double)? {
    for (i, s) in TL.scenes.enumerated() {
        if t >= s.start && t < s.start + s.dur {
            return (i, (t - s.start) / s.dur)
        }
    }
    return nil
}

// ===== Рендер видео =====
func pixelBuffer(from cg: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
    guard let buffer = pb else { return nil }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let ctx = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
    return buffer
}

@MainActor
func renderVideo(to path: String) async throws {
    try? FileManager.default.removeItem(atPath: path)
    let writer = try AVAssetWriter(outputURL: URL(fileURLWithPath: path), fileType: .mp4)
    let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
    writer.add(input)
    writer.startWriting(); writer.startSession(atSourceTime: .zero)

    let totalFrames = Int(TL.total * Double(FPS))
    var f = 0
    while f < totalFrames {
        if !input.isReadyForMoreMediaData { usleep(3000); continue }
        let t = Double(f) / Double(FPS)
        let renderer = ImageRenderer(content: FrameView(t: t))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: CGFloat(W), height: CGFloat(H))
        if let cg = renderer.cgImage, let pool = adaptor.pixelBufferPool,
           let buf = pixelBuffer(from: cg, pool: pool) {
            adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(FPS)))
        }
        if f % 90 == 0 { print("frame \(f)/\(totalFrames)") }
        f += 1
    }
    input.markAsFinished()
    await finishAsync(writer)
    print("video-only done: \(path)")
}

// ===== Склейка с озвучкой =====
func muxAudio(video: String, output: String, voGain: Float = 1.0) async throws {
    try? FileManager.default.removeItem(atPath: output)
    let comp = AVMutableComposition()
    let vAsset = AVURLAsset(url: URL(fileURLWithPath: video))
    let vRange = CMTimeRange(start: .zero, duration: vAsset.duration)
    let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try vTrack.insertTimeRange(vRange, of: vAsset.tracks(withMediaType: .video).first!, at: .zero)
    let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    for s in TL.scenes {
        let aAsset = AVURLAsset(url: URL(fileURLWithPath: s.voFile))
        guard let at = aAsset.tracks(withMediaType: .audio).first else { continue }
        try aTrack.insertTimeRange(CMTimeRange(start: .zero, duration: at.timeRange.duration), of: at,
                                   at: CMTime(seconds: s.voStart, preferredTimescale: 600))
    }
    aTrack.preferredVolume = voGain
    let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
    export.outputURL = URL(fileURLWithPath: output)
    export.outputFileType = .mp4
    await exportAsync(export)
    if let e = export.error { print("export error: \(e)") }
    print("final: \(output)")
}

func finishAsync(_ w: AVAssetWriter) async {
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        w.finishWriting { c.resume() }
    }
}
func exportAsync(_ e: AVAssetExportSession) async {
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        e.exportAsynchronously { c.resume() }
    }
}

// ===== main =====
let outDir = "/Users/user/Documents/project/IGoogle/docs"
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let videoOnly = "/tmp/igoogle_video_only.mp4"
let final = "\(outDir)/IGoogle-demo.mp4"
var finished = false
Task { @MainActor in
    do {
        try await renderVideo(to: videoOnly)
        try await muxAudio(video: videoOnly, output: final)
    } catch { print("ERROR: \(error)") }
    finished = true
}
while !finished { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
print("DONE")
