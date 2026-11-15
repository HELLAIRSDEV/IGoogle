import Foundation

/// Платформа устройства. Дублируется в общем Kotlin-модуле (`shared`),
/// чтобы сетевой контракт был одинаковым на macOS и Android.
public enum IGooglePlatform: String, Codable, Sendable {
    case macos
    case android
    case unknown
}

/// Типы сообщений, которыми обмениваются Mac и Pixel.
public enum MessageType: String, Codable, Sendable {
    case hello
    case goodbye
    case clipboard
    case ping
    case pong
    case fileMeta = "file_meta"
    case ack
}

/// Идентификатор устройства-участника.
public struct DeviceInfo: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var platform: IGooglePlatform

    public init(id: String, name: String, platform: IGooglePlatform) {
        self.id = id
        self.name = name
        self.platform = platform
    }
}

/// Полезная нагрузка общего буфера обмена.
public struct ClipboardPayload: Codable, Equatable, Sendable {
    public var text: String
    public var timestamp: TimeInterval

    public init(text: String, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.text = text
        self.timestamp = timestamp
    }
}

/// Метаданные файла для передачи «Pixel → MacBook» (аналог AirDrop).
public struct FileMetaPayload: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var size: Int64
    public var mime: String

    public init(id: String, name: String, size: Int64, mime: String = "application/octet-stream") {
        self.id = id
        self.name = name
        self.size = size
        self.mime = mime
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, size, mime
    }

    /// Терпимый декодер: Android (kotlinx.serialization) опускает поля,
    /// равные значению по умолчанию, поэтому `mime` может отсутствовать.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "file"
        size = try container.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        mime = try container.decodeIfPresent(String.self, forKey: .mime) ?? "application/octet-stream"
    }
}

/// Единый конверт сообщения. Плоская структура (опциональные поля вместо
/// enum с ассоциированными значениями) намеренно зеркалит `@Serializable`
/// data class из Kotlin Multiplatform — так JSON совпадает на обеих платформах.
public struct Message: Codable, Equatable, Sendable {
    public var type: MessageType
    public var device: DeviceInfo?
    public var clipboard: ClipboardPayload?
    public var file: FileMetaPayload?
    public var timestamp: TimeInterval

    public init(
        type: MessageType,
        device: DeviceInfo? = nil,
        clipboard: ClipboardPayload? = nil,
        file: FileMetaPayload? = nil,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.type = type
        self.device = device
        self.clipboard = clipboard
        self.file = file
        self.timestamp = timestamp
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public func encodedText() throws -> String {
        String(data: try encoded(), encoding: .utf8) ?? ""
    }

    public static func decode(_ data: Data) throws -> Message {
        try JSONDecoder().decode(Message.self, from: data)
    }

    public static func decode(_ text: String) throws -> Message {
        try decode(Data(text.utf8))
    }
}
