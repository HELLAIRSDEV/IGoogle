package com.igoogle.shared

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Сетевой протокол IGoogle. Эти data-классы в точности повторяют
 * `Models.swift` из macOS-приложения: JSON-формат совпадает на обеих
 * платформах, поэтому Mac и Pixel понимают друг друга без адаптеров.
 */

@Serializable
enum class Platform {
    @SerialName("macos") MACOS,
    @SerialName("android") ANDROID,
    @SerialName("unknown") UNKNOWN,
}

@Serializable
enum class MessageType {
    @SerialName("hello") HELLO,
    @SerialName("goodbye") GOODBYE,
    @SerialName("clipboard") CLIPBOARD,
    @SerialName("ping") PING,
    @SerialName("pong") PONG,
    @SerialName("file_meta") FILE_META,
    @SerialName("ack") ACK,
}

@Serializable
data class DeviceInfo(
    val id: String,
    val name: String,
    val platform: Platform = Platform.UNKNOWN,
)

@Serializable
data class ClipboardPayload(
    val text: String,
    val timestamp: Double = currentTimestampSeconds(),
)

@Serializable
data class FileMetaPayload(
    val id: String,
    val name: String,
    val size: Long,
    val mime: String = "application/octet-stream",
)

@Serializable
data class Message(
    val type: MessageType,
    val device: DeviceInfo? = null,
    val clipboard: ClipboardPayload? = null,
    val file: FileMetaPayload? = null,
    val timestamp: Double = currentTimestampSeconds(),
) {
    fun encode(): String = protocolJson.encodeToString(this)

    companion object {
        // encodeDefaults=true — всегда пишем timestamp/mime и пр., чтобы вторая
        // сторона (Swift) не спотыкалась на отсутствующих полях.
        val protocolJson: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

        fun decode(text: String): Message = protocolJson.decodeFromString(text)
    }
}
