import Foundation
import Network
import CryptoKit

// MARK: - Кадры WebSocket

public enum WebSocketOpcode: UInt8 {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA
}

public struct WebSocketFrame {
    public let fin: Bool
    public let opcode: WebSocketOpcode
    public let payload: Data

    public init(fin: Bool, opcode: WebSocketOpcode, payload: Data) {
        self.fin = fin
        self.opcode = opcode
        self.payload = payload
    }
}

/// Кодирование кадров (сервер -> клиент, без маски).
public enum WebSocketFrameEncode {
    public static func encode(opcode: WebSocketOpcode, payload: Data, fin: Bool = true) -> Data {
        var data = Data()
        data.append((fin ? 0x80 : 0x00) | opcode.rawValue)
        let length = payload.count
        if length < 126 {
            data.append(UInt8(length))
        } else if length <= 0xFFFF {
            data.append(126)
            data.append(UInt8((length >> 8) & 0xFF))
            data.append(UInt8(length & 0xFF))
        } else {
            data.append(127)
            var big = UInt64(length).bigEndian
            withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
        }
        data.append(payload)
        return data
    }
}

public enum WebSocketFrameParseError: Error {
    case malformed
}

public enum WebSocketFrameParseResult {
    case frame(WebSocketFrame)
    case incomplete
}

/// Потоковый парсер кадров (клиент -> сервер, с маской).
public struct WebSocketFrameDecoder {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) {
        buffer.append(data)
    }

    public mutating func parse() throws -> WebSocketFrameParseResult {
        guard buffer.count >= 2 else { return .incomplete }
        let b0 = buffer[0]
        let b1 = buffer[1]
        let fin = (b0 & 0x80) != 0
        guard let opcode = WebSocketOpcode(rawValue: b0 & 0x0F) else {
            throw WebSocketFrameParseError.malformed
        }
        let masked = (b1 & 0x80) != 0
        var length = UInt64(b1 & 0x7F)
        var offset = 2

        if length == 126 {
            guard buffer.count >= offset + 2 else { return .incomplete }
            length = (UInt64(buffer[offset]) << 8) | UInt64(buffer[offset + 1])
            offset += 2
        } else if length == 127 {
            guard buffer.count >= offset + 8 else { return .incomplete }
            var value: UInt64 = 0
            for i in 0..<8 {
                value = (value << 8) | UInt64(buffer[offset + i])
            }
            length = value
            offset += 8
        }

        var maskKey = [UInt8]()
        if masked {
            guard buffer.count >= offset + 4 else { return .incomplete }
            maskKey = Array(buffer[offset..<offset + 4])
            offset += 4
        }

        guard length <= UInt64(Int.max) else { throw WebSocketFrameParseError.malformed }
        let payloadLength = Int(length)
        guard buffer.count >= offset + payloadLength else { return .incomplete }

        var payload = Data(buffer[offset..<offset + payloadLength])
        if masked {
            for i in 0..<payload.count {
                payload[i] ^= maskKey[i % 4]
            }
        }
        buffer.removeSubrange(0..<(offset + payloadLength))
        return .frame(WebSocketFrame(fin: fin, opcode: opcode, payload: payload))
    }
}

public enum WebSocketHandshakeError: Error {
    case missingKey
    case incomplete
}

// MARK: - Подключение

/// Одно WebSocket-подключение поверх `NWConnection`.
public final class WebSocketConnection: Hashable {
    public let id = UUID()
    let connection: NWConnection
    private let queue: DispatchQueue
    private var decoder = WebSocketFrameDecoder()
    private var headerBuffer = Data()
    private var didNotifyClose = false

    public var onText: ((String) -> Void)?
    public var onBinary: ((Data) -> Void)?
    public var onClose: (() -> Void)?

    init(connection: NWConnection) {
        self.connection = connection
        self.queue = DispatchQueue(label: "com.igoogle.ws.\(UUID().uuidString)")
    }

    public static func == (lhs: WebSocketConnection, rhs: WebSocketConnection) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: Handshake

    func performHandshake(completion: @escaping (Result<Void, Error>) -> Void) {
        connection.start(queue: queue)
        readHeaders { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let requestText):
                guard let key = Self.headerValue("Sec-WebSocket-Key", in: requestText) else {
                    completion(.failure(WebSocketHandshakeError.missingKey))
                    return
                }
                let accept = Self.computeAccept(key)
                let response = "HTTP/1.1 101 Switching Protocols\r\n" +
                    "Upgrade: websocket\r\n" +
                    "Connection: Upgrade\r\n" +
                    "Sec-WebSocket-Accept: \(accept)\r\n\r\n"
                self.sendRaw(response.data(using: .utf8)!) { error in
                    if let error {
                        completion(.failure(error))
                    } else {
                        // Оставшиеся после заголовка байты (если есть) — начало кадров.
                        if !self.headerBuffer.isEmpty {
                            self.decoder.append(self.headerBuffer)
                            self.headerBuffer.removeAll()
                        }
                        completion(.success(()))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func readHeaders(completion: @escaping (Result<String, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                completion(.failure(error))
                return
            }
            if let data {
                self.headerBuffer.append(data)
            }
            if let range = self.headerBuffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = self.headerBuffer[..<range.lowerBound]
                self.headerBuffer.removeSubrange(0..<range.upperBound)
                completion(.success(String(data: headerData, encoding: .utf8) ?? ""))
            } else if isComplete {
                completion(.failure(WebSocketHandshakeError.incomplete))
            } else {
                self.readHeaders(completion: completion)
            }
        }
    }

    // MARK: Чтение кадров

    func startReading() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                self.notifyClosed()
                return
            }
            if let data {
                self.decoder.append(data)
            }
            self.processFrames()
            if isComplete {
                self.notifyClosed()
            } else {
                self.startReading()
            }
        }
    }

    private func processFrames() {
        while true {
            do {
                switch try decoder.parse() {
                case .frame(let frame):
                    handle(frame)
                case .incomplete:
                    return
                }
            } catch {
                notifyClosed()
                return
            }
        }
    }

    private func handle(_ frame: WebSocketFrame) {
        switch frame.opcode {
        case .text:
            if let text = String(data: frame.payload, encoding: .utf8) {
                onText?(text)
            }
        case .binary:
            onBinary?(frame.payload)
        case .ping:
            sendRaw(WebSocketFrameEncode.encode(opcode: .pong, payload: frame.payload), completion: nil)
        case .pong:
            break
        case .close:
            notifyClosed()
        default:
            break
        }
    }

    // MARK: Отправка

    public func send(text: String) {
        sendRaw(WebSocketFrameEncode.encode(opcode: .text, payload: Data(text.utf8)), completion: nil)
    }

    public func send(data: Data) {
        sendRaw(WebSocketFrameEncode.encode(opcode: .binary, payload: data), completion: nil)
    }

    public func close() {
        sendRaw(WebSocketFrameEncode.encode(opcode: .close, payload: Data()), completion: nil)
        notifyClosed()
    }

    private func sendRaw(_ data: Data, completion: ((NWError?) -> Void)?) {
        connection.send(content: data, completion: .contentProcessed { error in
            completion?(error)
        })
    }

    private func notifyClosed() {
        guard !didNotifyClose else { return }
        didNotifyClose = true
        connection.cancel()
        onClose?()
    }

    // MARK: Helpers

    private static func headerValue(_ name: String, in request: String) -> String? {
        for line in request.components(separatedBy: "\r\n") {
            let parts = line.components(separatedBy: ":")
            if parts.count >= 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == name.lowercased() {
                return parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func computeAccept(_ key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data((key + magic).utf8))
        return Data(digest).base64EncodedString()
    }
}

// MARK: - Сервер

/// Bonjour-объявляемый WebSocket-сервер. Android находит его через NSD и
/// подключается как клиент.
public final class WebSocketServer {
    public let serviceType: String
    public let serviceName: String

    private let queue = DispatchQueue(label: "com.igoogle.server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: Set<WebSocketConnection> = []

    public var onConnect: ((WebSocketConnection) -> Void)?
    public var onDisconnect: ((WebSocketConnection) -> Void)?
    public var onMessage: ((String, WebSocketConnection) -> Void)?
    public var onData: ((Data, WebSocketConnection) -> Void)?

    public private(set) var port: UInt16 = 0

    public init(serviceType: String = "_igoogle._tcp", serviceName: String = "MacBook") {
        self.serviceType = serviceType
        self.serviceName = serviceName
    }

    public func start() throws {
        let listener = try NWListener(using: .tcp)
        self.listener = listener
        listener.service = NWListener.Service(name: serviceName, type: serviceType)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.port = self?.listener?.port?.rawValue ?? 0
                print("[IGoogle] слушаю на порту \(self?.port ?? 0), сервис \(self?.serviceType ?? "")")
            case .failed(let error):
                print("[IGoogle] ошибка слушателя: \(error)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        let snapshot = connections
        connections.removeAll()
        lock.unlock()
        for connection in snapshot {
            connection.close()
        }
    }

    private func accept(_ connection: NWConnection) {
        let ws = WebSocketConnection(connection: connection)
        // Сильно удерживаем ws на время рукопожатия, иначе оно освободится
        // раньше, чем придёт HTTP-запрос от клиента.
        ws.performHandshake { [weak self, ws] result in
            guard let self else { return }
            switch result {
            case .success:
                ws.onText = { [weak self] text in
                    self?.onMessage?(text, ws)
                }
                ws.onBinary = { [weak self] data in
                    self?.onData?(data, ws)
                }
                ws.onClose = { [weak self] in
                    guard let self else { return }
                    self.lock.lock()
                    self.connections.remove(ws)
                    self.lock.unlock()
                    self.onDisconnect?(ws)
                }
                self.lock.lock()
                self.connections.insert(ws)
                self.lock.unlock()
                ws.startReading()
                self.onConnect?(ws)
            case .failure(let error):
                print("[IGoogle] рукопожатие не удалось: \(error)")
                connection.cancel()
            }
        }
    }

    public var connectedPeers: [WebSocketConnection] {
        lock.lock()
        defer { lock.unlock() }
        return Array(connections)
    }

    public func broadcast(text: String) {
        lock.lock()
        let snapshot = connections
        lock.unlock()
        for connection in snapshot {
            connection.send(text: text)
        }
    }

    public func broadcast(data: Data) {
        lock.lock()
        let snapshot = connections
        lock.unlock()
        for connection in snapshot {
            connection.send(data: data)
        }
    }
}
