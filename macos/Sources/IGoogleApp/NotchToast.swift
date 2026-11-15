import AppKit
import SwiftUI
import Combine
import IGoogleCore

/// «Островок» под вырезом MacBook: капсула шириной с вырез, верх заподлицо с
/// экраном (как будто выезжает из чёлки), скругление только снизу.
final class NotchToast {
    static let shared = NotchToast()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let model = NotchModel()
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(
            forName: IGoogleHub.receivedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let title = note.userInfo?["title"] as? String ?? "IGoogle"
            let detail = note.userInfo?["detail"] as? String ?? ""
            let icon = note.userInfo?["icon"] as? String ?? "sparkles"
            self?.show(title: title, detail: detail, icon: icon)
        }
    }

    private var screen: NSScreen? { NSScreen.main ?? NSScreen.screens.first }

    func show(title: String, detail: String, icon: String) {
        guard let screen else { return }
        let metrics = notchMetrics(screen)

        model.width = metrics.width
        model.notchHeight = metrics.height
        model.title = title
        model.detail = detail
        model.icon = icon
        model.isExpanded = false

        ensurePanel(on: screen, metrics: metrics)
        panel?.orderFrontRegardless()

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                self.model.isExpanded = true
            }
        }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                self.model.isExpanded = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.panel?.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: work)
    }

    /// Ширина и высота выреза (по областям слева/справа от него).
    private func notchMetrics(_ screen: NSScreen) -> (width: CGFloat, height: CGFloat) {
        let safeTop = screen.safeAreaInsets.top
        let height = safeTop > 1 ? safeTop : max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            if width > 1 {
                return (width, height)
            }
        }
        return (max(160, height * 5), height)
    }

    private func ensurePanel(on screen: NSScreen, metrics: (width: CGFloat, height: CGFloat)) {
        let frame = panelFrame(screen, metrics: metrics)
        if let panel {
            panel.setFrame(frame, display: true)
            return
        }
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: NotchToastView(model: model))
        self.panel = panel
    }

    private func panelFrame(_ screen: NSScreen, metrics: (width: CGFloat, height: CGFloat)) -> NSRect {
        let width = metrics.width + 4
        let height = metrics.height + 120
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }
}

final class NotchModel: ObservableObject {
    @Published var isExpanded = false
    @Published var title = ""
    @Published var detail = ""
    @Published var icon = "sparkles"
    @Published var width: CGFloat = 200
    @Published var notchHeight: CGFloat = 37
}

/// Форма с прямым верхом и закруглённым низом.
struct BottomRoundedShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct NotchToastView: View {
    @ObservedObject var model: NotchModel

    private var contentHeight: CGFloat { model.detail.isEmpty ? 22 : 34 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: model.notchHeight)

            if model.isExpanded {
                HStack(spacing: 6) {
                    Image(systemName: model.icon)
                        .font(.system(size: 12, weight: .semibold))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        if !model.detail.isEmpty {
                            Text(model.detail)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .frame(width: model.width, height: contentHeight)
                .transition(.opacity)
            }
        }
        .frame(width: model.width)
        .background(BottomRoundedShape(radius: 13).fill(Color.black))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
    }
}
