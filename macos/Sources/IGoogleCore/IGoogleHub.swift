import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

/// Отладочный лог Mac-хаба в файл (stdout из фонового процесса буферизуется).
func macLog(_ message: String) {
    let line = "\(Date()) \(message)\n"
    let url = URL(fileURLWithPath: "/tmp/igoogle-mac.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}

/// Устройство-участник, отображаемое в UI.
public struct Peer: Identifiable, Equatable {
    public let id: String
    public var name: String
    public var platform: IGooglePlatform
    public var lastSeen: Date
    public var connected: Bool

    public init(id: String, name: String, platform: IGooglePlatform, lastSeen: Date = Date(), connected: Bool = true) {
        self.id = id
        self.name = name
        self.platform = platform
        self.lastSeen = lastSeen
        self.connected = connected
    }
}

/// Состояние принимаемого файла (пишется по кускам в `~/Downloads/IGoogle`).
private struct IncomingFile {
    let id: String
    let name: String
    let size: Int64
    let mime: String
    var received: Int64 = 0
    let handle: FileHandle
}

/// Оркестратор: связывает WebSocket-сервер, Bonjour, буфер обмена и состояние UI.
/// Это «хаб» приложения — та же логика на Android реализована в `shared` (KMP).
public final class IGoogleHub: ObservableObject {
    /// Событие «получено с Pixel» для UI-островка (буфер/файл/фото).
    public static let receivedNotification = Notification.Name("IGoogle.received")

    @Published public private(set) var peers: [Peer] = []
    @Published public private(set) var lastTransfer: String?
    @Published public private(set) var lastTransferAt: Date?
    @Published public private(set) var isRunning = false

    /// Принимать входящий буфер с Pixel.
    @Published public var receiveClipboard = true
    /// «Бесшовный режим»: keep-alive ping + мгновенное обнаружение обрывов.
    @Published public var seamlessMode = true

    /// Куда сохранять входящие фото (nil → ~/Downloads/IGoogle).
    @Published public var photoSaveDirectory: URL? {
        didSet {
            UserDefaults.standard.set(photoSaveDirectory?.path, forKey: "IGoogle.photoDir")
        }
    }

    public let localDevice: DeviceInfo

    private let server: WebSocketServer
    private let monitor = ClipboardMonitor()
    private let pasteboard = NSPasteboard.general

    private var suppressNextClipboard = false
    private var deviceByConnection: [UUID: DeviceInfo] = [:]
    private var connectionByPeer: [String: WebSocketConnection] = [:]
    private var pingTimer: Timer?
    private var incomingFiles: [String: IncomingFile] = [:]
    private let receivedDirectory: URL

    public init(serviceName: String? = nil) {
        let name = serviceName ?? (Host.current().localizedName ?? "MacBook")
        localDevice = DeviceInfo(id: Self.macDeviceID, name: name, platform: .macos)
        server = WebSocketServer(serviceType: "_igoogle._tcp", serviceName: name)

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        receivedDirectory = downloads.appendingPathComponent("IGoogle", isDirectory: true)
        try? FileManager.default.createDirectory(at: receivedDirectory, withIntermediateDirectories: true)
        if let savedPhotoDir = UserDefaults.standard.string(forKey: "IGoogle.photoDir") {
            photoSaveDirectory = URL(fileURLWithPath: savedPhotoDir)
        }

        server.onMessage = { [weak self] text, connection in
            DispatchQueue.main.async { self?.handleMessage(text, from: connection) }
        }
        server.onData = { [weak self] data, connection in
            DispatchQueue.main.async { self?.handleBinary(data, from: connection) }
        }
        server.onDisconnect = { [weak self] connection in
            DispatchQueue.main.async { self?.handleDisconnect(connection) }
        }
        monitor.onChange = { [weak self] text in
            DispatchQueue.main.async { self?.handleLocalClipboardChange(text) }
        }
    }

    public func start() throws {
        guard !isRunning else { return }
        try server.start()
        monitor.start()
        isRunning = true
        if seamlessMode {
            startPing()
        }
    }

    public func stop() {
        monitor.stop()
        pingTimer?.invalidate()
        pingTimer = nil
        server.stop()
        isRunning = false
        peers = []
    }

    // MARK: Keep-alive («бесшовный режим»)

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.tickPing()
        }
        if let pingTimer {
            RunLoop.main.add(pingTimer, forMode: .common)
        }
    }

    private func tickPing() {
        broadcast(Message(type: .ping, device: localDevice))
        // Помечаем «офлайн» тех, кто не отвечал дольше двух интервалов.
        let cutoff = Date().addingTimeInterval(-30)
        var updated = peers
        var changed = false
        for i in updated.indices where updated[i].connected && updated[i].lastSeen < cutoff {
            updated[i].connected = false
            changed = true
        }
        if changed {
            peers = updated
        }
    }

    // MARK: Входящие сообщения

    private func handleMessage(_ text: String, from connection: WebSocketConnection) {
        let msg: Message
        do {
            msg = try Message.decode(text)
        } catch {
            macLog("decode FAILED: \(error) | text=\(text)")
            return
        }
        macLog("recv type=\(msg.type.rawValue)")
        switch msg.type {
        case .hello:
            guard let device = msg.device else { return }
            deviceByConnection[connection.id] = device
            connectionByPeer[device.id] = connection
            upsertPeer(device, connected: true)
            // Отвечаем своим hello, чтобы Pixel узнал наш id/имя.
            connection.send(text: (try? Message(type: .hello, device: localDevice).encodedText()) ?? "")
        case .goodbye:
            if let device = msg.device {
                removePeer(device.id)
            }
        case .clipboard:
            if let clip = msg.clipboard {
                applyRemoteClipboard(clip.text, from: msg.device)
            }
        case .ping:
            connection.send(text: (try? Message(type: .pong, device: localDevice).encodedText()) ?? "")
        case .pong:
            if let device = msg.device {
                markSeen(device)
            }
        case .fileMeta:
            if let file = msg.file {
                receiveFileMeta(file, from: connection)
            }
        case .ack:
            break
        }
    }

    private func handleBinary(_ data: Data, from connection: WebSocketConnection) {
        receiveFileChunk(data)
    }

    private func handleDisconnect(_ connection: WebSocketConnection) {
        if let device = deviceByConnection.removeValue(forKey: connection.id) {
            connectionByPeer.removeValue(forKey: device.id)
            markDisconnected(device.id)
        }
    }

    // MARK: Буфер обмена

    private func handleLocalClipboardChange(_ text: String) {
        if suppressNextClipboard {
            suppressNextClipboard = false
            return
        }
        let msg = Message(type: .clipboard, device: localDevice, clipboard: ClipboardPayload(text: text))
        broadcast(msg)
    }

    private func applyRemoteClipboard(_ text: String, from device: DeviceInfo?) {
        macLog("applyRemoteClipboard receiveClipboard=\(receiveClipboard) text=\(text.prefix(30))")
        guard receiveClipboard else { return }
        suppressNextClipboard = true
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastTransfer = text
        lastTransferAt = Date()
        NotificationCenter.default.post(name: Self.receivedNotification, object: nil, userInfo: [
            "title": "Получен буфер",
            "detail": text,
            "icon": "doc.on.clipboard.fill",
        ])
        if let device {
            markSeen(device)
        }
    }

    // MARK: Передача файлов (AirDrop-аналог)

    private func receiveFileMeta(_ file: FileMetaPayload, from connection: WebSocketConnection) {
        // Нормализуем id к каноническому виду UUID (Swift — верхний регистр),
        // чтобы он совпал с ключом из бинарных чанков.
        let key = UUID(uuidString: file.id)?.uuidString ?? file.id
        do {
            let isImage = file.mime.hasPrefix("image/")
            let directory = (isImage ? photoSaveDirectory : nil) ?? receivedDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = uniqueURL(in: directory, name: file.name)
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { return }
            let handle = try FileHandle(forWritingTo: destination)
            incomingFiles[key] = IncomingFile(id: key, name: file.name, size: file.size, mime: file.mime, handle: handle)
            lastTransfer = "📥 Получение: \(file.name)"
            lastTransferAt = Date()
            macLog("file meta: \(file.name) size=\(file.size)")
        } catch {
            macLog("file meta error: \(error)")
            return
        }
        // Подтверждаем готовность принимать кадры.
        let ack = (try? Message(type: .ack, device: localDevice, file: file).encodedText()) ?? ""
        connection.send(text: ack)
    }

    private func receiveFileChunk(_ data: Data) {
        guard let (id, offset, chunk) = FileChunk.decode(data),
              var incoming = incomingFiles[id.uuidString] else { return }
        do {
            try incoming.handle.seek(toOffset: offset)
            incoming.handle.write(chunk)
            incoming.received += Int64(chunk.count)
        } catch {
            print("[IGoogle] ошибка записи: \(error)")
            return
        }

        if incoming.received >= incoming.size {
            try? incoming.handle.close()
            incomingFiles.removeValue(forKey: id.uuidString)
            lastTransfer = "📁 \(incoming.name)"
            lastTransferAt = Date()
            print("[IGoogle] файл сохранён: \(incoming.name)")
            let isImage = incoming.mime.hasPrefix("image/")
            NotificationCenter.default.post(name: Self.receivedNotification, object: nil, userInfo: [
                "title": isImage ? "Получено фото" : "Получен файл",
                "detail": incoming.name,
                "icon": isImage ? "photo.fill" : "doc.fill",
            ])
        } else {
            incomingFiles[id.uuidString] = incoming
        }
    }

    /// Отправка файла с Mac на Pixel (перетаскивание в drop-зону).
    public func sendFile(_ url: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let id = UUID()
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let meta = FileMetaPayload(id: id.uuidString, name: url.lastPathComponent, size: size, mime: mime)
            self.broadcast(Message(type: .fileMeta, device: self.localDevice, file: meta))

            guard let handle = try? FileHandle(forReadingFrom: url) else { return }
            let chunkSize = 64 * 1024
            var offset: UInt64 = 0
            while true {
                let data = handle.readData(ofLength: chunkSize)
                if data.isEmpty { break }
                self.server.broadcast(data: FileChunk.encode(id: id, offset: offset, data: data))
                offset += UInt64(data.count)
            }
            try? handle.close()

            DispatchQueue.main.async {
                self.lastTransfer = "📤 \(url.lastPathComponent)"
                self.lastTransferAt = Date()
            }
        }
    }

    private func uniqueURL(in directory: URL, name: String) -> URL {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(name)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = ext.isEmpty ? " (\(index))" : " (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(base + suffix)
            index += 1
        }
        return candidate
    }

    // MARK: Учёт устройств

    private func upsertPeer(_ device: DeviceInfo, connected: Bool) {
        var updated = peers
        if let idx = updated.firstIndex(where: { $0.id == device.id }) {
            updated[idx].name = device.name
            updated[idx].platform = device.platform
            updated[idx].lastSeen = Date()
            updated[idx].connected = connected
        } else {
            updated.append(Peer(id: device.id, name: device.name, platform: device.platform, lastSeen: Date(), connected: connected))
        }
        peers = updated
    }

    private func markSeen(_ device: DeviceInfo) {
        if let idx = peers.firstIndex(where: { $0.id == device.id }) {
            peers[idx].lastSeen = Date()
            peers[idx].connected = true
        }
    }

    private func markDisconnected(_ id: String) {
        if let idx = peers.firstIndex(where: { $0.id == id }) {
            peers[idx].connected = false
        }
    }

    private func removePeer(_ id: String) {
        peers.removeAll { $0.id == id }
    }

    // MARK: Отправка

    public func broadcast(_ message: Message) {
        // Протокольные сообщения — текстовым кадром (JSON).
        // Бинарными кадрами передаются только чанки файлов (см. sendFile).
        if let text = try? message.encodedText() {
            server.broadcast(text: text)
        }
    }

    public func pushCurrentClipboard() {
        guard let text = pasteboard.string(forType: .string) else { return }
        let msg = Message(type: .clipboard, device: localDevice, clipboard: ClipboardPayload(text: text))
        broadcast(msg)
        lastTransfer = text
        lastTransferAt = Date()
    }

    /// Отправить изображение из буфера Mac как файл (уйдёт в «Фото» на Pixel).
    public func pushClipboardImage() {
        let png = pasteboard.data(forType: .png)
        let tiff = png == nil ? pasteboard.data(forType: .tiff) : nil
        guard let data = png ?? tiff else { return }
        let ext = png != nil ? "png" : "tiff"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ig-\(UUID().uuidString).\(ext)")
        guard (try? data.write(to: url)) != nil else { return }
        sendFile(url)
    }

    // MARK: Идентификатор

    private static var macDeviceID: String {
        let key = "IGoogle.macDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let id = "mac-" + UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
