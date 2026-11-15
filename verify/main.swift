// Проверочный харнесс: запускает WebSocket-сервер, подключается к нему
// минимальным клиентом по TCP, делает рукопожатие и шлёт замаскированный
// кадр с JSON-сообщением буфера обмена. Не требует XCTest/Xcode.
import Foundation
import Network
import CryptoKit

// MARK: - Минимальный WebSocket-клиент для проверки сервера

func computeAccept(_ key: String) -> String {
    let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    let digest = Insecure.SHA1.hash(data: Data((key + magic).utf8))
    return Data(digest).base64EncodedString()
}

func maskedFrame(opcode: UInt8, payload: Data) -> Data {
    var data = Data()
    data.append(0x80 | opcode)
    let len = payload.count
    if len < 126 {
        data.append(0x80 | UInt8(len))
    } else {
        data.append(0x80 | 126)
        data.append(UInt8((len >> 8) & 0xFF))
        data.append(UInt8(len & 0xFF))
    }
    var mask = [UInt8](repeating: 0, count: 4)
    for i in 0..<4 { mask[i] = UInt8.random(in: 0...255) }
    data.append(contentsOf: mask)
    for (i, b) in payload.enumerated() { data.append(b ^ mask[i % 4]) }
    return data
}

var failures = 0
func expect(_ cond: Bool, _ name: String) {
    print((cond ? "✅" : "❌") + " " + name)
    if !cond { failures += 1 }
}

// 1. Кодек кадров: разные длины
for length in [0, 125, 126, 65535, 65536, 70000] {
    var d = WebSocketFrameDecoder()
    let payload = Data(repeating: 0xAB, count: length)
    d.append(WebSocketFrameEncode.encode(opcode: .binary, payload: payload))
    if case .frame(let f) = try? d.parse() {
        expect(f.payload == payload, "кадр длины \(length)")
    } else {
        expect(false, "кадр длины \(length)")
    }
}

// 2. Замаскированный кадр от клиента
do {
    var d = WebSocketFrameDecoder()
    d.append(maskedFrame(opcode: 1, payload: Data("hello".utf8)))
    if case .frame(let f) = try d.parse() {
        expect(f.payload == Data("hello".utf8), "замаскированный кадр")
    } else {
        expect(false, "замаскированный кадр")
    }
}

// 3. JSON-протокол
do {
    let m = Message(
        type: .clipboard,
        device: DeviceInfo(id: "px-1", name: "Pixel 8", platform: .android),
        clipboard: ClipboardPayload(text: "привет с Pixel")
    )
    let decoded = try Message.decode(m.encoded())
    expect(decoded == m, "JSON round-trip")
}

// 3.5. Формат бинарного кадра файла (16 байт UUID + 8 байт offset + данные)
do {
    let id = UUID()
    let payload = Data(repeating: 0x5C, count: 1000)
    let frame = FileChunk.encode(id: id, offset: 128, data: payload)
    if let decoded = FileChunk.decode(frame) {
        expect(decoded.id == id && decoded.offset == 128 && decoded.data == payload, "chunk round-trip")
    } else {
        expect(false, "chunk round-trip")
    }
}

// 4. Живой сервер + клиент по TCP
let sem = DispatchSemaphore(value: 0)
let server = WebSocketServer(serviceType: "_igoogle._tcp", serviceName: "TestMac")
var receivedOnServer: String?
server.onMessage = { text, _ in
    receivedOnServer = text
    print("debug: сервер onMessage")
    sem.signal()
}
server.onConnect = { _ in print("debug: сервер onConnect") }
server.onDisconnect = { _ in print("debug: сервер onDisconnect") }

do {
    try server.start()
} catch {
    expect(false, "запуск сервера: \(error)")
}

// ждём готовности слушателя (порт назначается асинхронно)
let deadline = Date().addingTimeInterval(5)
while server.port == 0 && Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
}
expect(server.port != 0, "порт назначен: \(server.port)")

let port = NWEndpoint.Port(rawValue: server.port)!
let conn = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
conn.stateUpdateHandler = { state in print("debug: состояние клиента \(state)") }
conn.start(queue: DispatchQueue(label: "client"))

let key = "dGhlIHNhbXBsZSBub25jZQ=="
let request = "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"
conn.send(content: request.data(using: .utf8)!, completion: .contentProcessed { _ in
    print("debug: клиент отправил запрос")
})

var clientBuffer = Data()
func receive() {
    conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
        if let error { print("debug: клиент получил ошибку \(error)") }
        if let data { clientBuffer.append(data); print("debug: клиент получил \(data.count) байт, всего \(clientBuffer.count)") }
        if clientBuffer.contains(Data("\r\n\r\n".utf8)) {
            let resp = String(data: clientBuffer, encoding: .utf8) ?? ""
            expect(resp.hasPrefix("HTTP/1.1 101"), "рукопожатие 101")
            expect(resp.contains("Sec-WebSocket-Accept: \(computeAccept(key))"), "ключ accept верен")
            let payload = try! Message(
                type: .clipboard,
                device: DeviceInfo(id: "px-1", name: "Pixel 8", platform: .android),
                clipboard: ClipboardPayload(text: "from-pixel")
            ).encoded()
            conn.send(content: maskedFrame(opcode: 1, payload: payload), completion: .contentProcessed { _ in })
        }
        if !isComplete { receive() }
    }
}
receive()

if sem.wait(timeout: .now() + 5) == .success {
    if let text = receivedOnServer,
       let msg = try? Message.decode(text) {
        expect(msg.type == .clipboard && msg.clipboard?.text == "from-pixel",
               "сервер принял clipboard-сообщение")
    } else {
        expect(false, "сервер декодировал сообщение")
    }
} else {
    expect(false, "сервер не получил сообщение (таймаут)")
}

server.stop()
print(failures == 0 ? "\nВСЕ ПРОВЕРКИ ПРОЙДЕНЫ" : "\nПРОВАЛОВ: \(failures)")
exit(failures == 0 ? 0 : 1)
