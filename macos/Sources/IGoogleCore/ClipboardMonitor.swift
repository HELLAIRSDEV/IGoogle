import Foundation
import AppKit

/// Следит за системным буфером обмена через `NSPasteboard.changeCount`.
/// Polling-подход выбран намеренно: он не требует приватных API и стабильно
/// работает без перехвата событий (это часть «бесшовного режима»).
public final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    /// Вызывается при изменении текста в буфере.
    public var onChange: ((String) -> Void)?
    public var pollingInterval: TimeInterval = 0.5

    public init() {
        lastChangeCount = pasteboard.changeCount
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // Позволяет таймеру работать при активном пользовательском вводе
        // (напр. во время drag-and-drop).
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard let text = pasteboard.string(forType: .string) else { return }
        onChange?(text)
    }
}
