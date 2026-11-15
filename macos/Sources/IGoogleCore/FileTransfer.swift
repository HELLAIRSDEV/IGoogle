import Foundation

extension UUID {
    /// 16 сырых байт UUID (для бинарных кадров файлов).
    var rawBytes: Data {
        var data = Data(count: 16)
        withUnsafeBytes(of: uuid) { source in
            data.withUnsafeMutableBytes { destination in
                destination.copyMemory(from: source)
            }
        }
        return data
    }

    /// Восстановление UUID из 16 байт.
    init?(rawBytes: Data) {
        guard rawBytes.count == 16 else { return nil }
        let value: uuid_t = rawBytes.withUnsafeBytes { $0.load(as: uuid_t.self) }
        self.init(uuid: value)
    }
}

/// Формат бинарного кадра передачи файла (одинаков на macOS и Android):
/// ```
/// [16 байт: UUID файла][8 байт: offset big-endian][данные…]
/// ```
public enum FileChunk {
    public static let headerSize = 24

    public static func encode(id: UUID, offset: UInt64, data: Data) -> Data {
        var frame = Data()
        frame.append(id.rawBytes)
        var offsetBE = offset.bigEndian
        withUnsafeBytes(of: &offsetBE) { frame.append(contentsOf: $0) }
        frame.append(data)
        return frame
    }

    public static func decode(_ data: Data) -> (id: UUID, offset: UInt64, data: Data)? {
        guard data.count > headerSize else { return nil }
        guard let id = UUID(rawBytes: data.prefix(16)) else { return nil }
        let offsetBytes = data[data.startIndex + 16 ..< data.startIndex + 24]
        let offset = offsetBytes.withUnsafeBytes { $0.load(as: UInt64.self) }.bigEndian
        return (id, offset, data.dropFirst(headerSize))
    }
}
