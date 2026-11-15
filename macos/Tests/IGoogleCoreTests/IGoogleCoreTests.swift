import XCTest
@testable import IGoogleCore

final class IGoogleCoreTests: XCTestCase {

    func testTextFrameRoundTrip() throws {
        var decoder = WebSocketFrameDecoder()
        let payload = Data("Привет, IGoogle".utf8)
        decoder.append(WebSocketFrameEncode.encode(opcode: .text, payload: payload))
        guard case .frame(let parsed) = try decoder.parse() else {
            return XCTFail("ожидался кадр")
        }
        XCTAssertEqual(parsed.opcode, .text)
        XCTAssertEqual(parsed.payload, payload)
    }

    func testFrameLengthBoundaries() throws {
        for length in [0, 125, 126, 65535, 65536, 70000] {
            var decoder = WebSocketFrameDecoder()
            let payload = Data(repeating: 0xAB, count: length)
            decoder.append(WebSocketFrameEncode.encode(opcode: .binary, payload: payload))
            guard case .frame(let parsed) = try decoder.parse() else {
                return XCTFail("ожидался кадр для длины \(length)")
            }
            XCTAssertEqual(parsed.payload, payload)
        }
    }

    func testMaskedClientFrame() throws {
        var decoder = WebSocketFrameDecoder()
        let payload = Data("abc".utf8)
        var data = Data()
        data.append(0x81) // FIN + text
        data.append(0x80 | UInt8(payload.count)) // masked + длина
        let mask: [UInt8] = [0x11, 0x22, 0x33, 0x44]
        data.append(contentsOf: mask)
        for (i, b) in payload.enumerated() {
            data.append(b ^ mask[i % 4])
        }
        decoder.append(data)
        guard case .frame(let parsed) = try decoder.parse() else {
            return XCTFail("ожидался замаскированный кадр")
        }
        XCTAssertEqual(parsed.payload, payload)
    }

    func testFragmentedFrameParsing() throws {
        var decoder = WebSocketFrameDecoder()
        let payload = Data(repeating: 0x5A, count: 300)
        let full = WebSocketFrameEncode.encode(opcode: .binary, payload: payload)
        let half = full.count / 2
        decoder.append(full.prefix(half))
        guard case .incomplete = try decoder.parse() else {
            return XCTFail("ожидался incomplete")
        }
        decoder.append(full.suffix(from: half))
        guard case .frame(let parsed) = try decoder.parse() else {
            return XCTFail("ожидался кадр после фрагментации")
        }
        XCTAssertEqual(parsed.payload, payload)
    }

    func testMessageJSONRoundTrip() throws {
        let msg = Message(
            type: .clipboard,
            device: DeviceInfo(id: "mac-1", name: "MacBook", platform: .macos),
            clipboard: ClipboardPayload(text: "hello")
        )
        let decoded = try Message.decode(msg.encoded())
        XCTAssertEqual(decoded, msg)
    }

    func testFileMetaJSONRoundTrip() throws {
        let msg = Message(
            type: .fileMeta,
            device: DeviceInfo(id: "px-1", name: "Pixel 8", platform: .android),
            file: FileMetaPayload(id: "f1", name: "photo.jpg", size: 12345, mime: "image/jpeg")
        )
        let decoded = try Message.decode(msg.encoded())
        XCTAssertEqual(decoded, msg)
    }
}
