package com.igoogle.shared

/** Колбэки движка передачи. */
interface TransferCallbacks {
    fun onRemoteClipboard(text: String, from: DeviceInfo?)
    fun onIncomingFile(meta: FileMetaPayload)
}

/**
 * Общая для macOS и Android логика синхронизации: маршрутизация входящих
 * сообщений и подавление «эха» буфера обмена (чтобы текст, который мы сами
 * только что записали из сети, не ушёл обратно отправителю бесконечным циклом).
 *
 * Транспорт не зависит от платформы и передаётся лямбдой `send`.
 */
class TransferEngine(
    private val local: DeviceInfo,
    private val callbacks: TransferCallbacks,
) {
    private var suppressNextClipboard = false

    fun onLocalClipboardChanged(text: String, send: (Message) -> Unit) {
        if (suppressNextClipboard) {
            suppressNextClipboard = false
            return
        }
        send(Message(type = MessageType.CLIPBOARD, device = local, clipboard = ClipboardPayload(text = text)))
    }

    fun onIncoming(message: Message) {
        when (message.type) {
            MessageType.CLIPBOARD -> message.clipboard?.let { clip ->
                suppressNextClipboard = true
                callbacks.onRemoteClipboard(clip.text, message.device)
            }
            MessageType.FILE_META -> message.file?.let(callbacks::onIncomingFile)
            else -> Unit
        }
    }
}
