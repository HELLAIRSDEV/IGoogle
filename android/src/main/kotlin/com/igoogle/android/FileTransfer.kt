package com.igoogle.android

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import com.igoogle.shared.DeviceInfo
import com.igoogle.shared.FileMetaPayload
import com.igoogle.shared.Message
import com.igoogle.shared.MessageType
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

// Формат бинарного кадра (одинаков с macOS FileTransfer.swift):
// [16 байт UUID][8 байт offset big-endian][данные…]
const val CHUNK_HEADER_SIZE = 24

fun encodeChunk(id: UUID, offset: Long, data: ByteArray): ByteArray {
    val buf = ByteBuffer.allocate(CHUNK_HEADER_SIZE + data.size).order(ByteOrder.BIG_ENDIAN)
    buf.putLong(id.mostSignificantBits)
    buf.putLong(id.leastSignificantBits)
    buf.putLong(offset)
    buf.put(data)
    return buf.array()
}

class DecodedChunk(val id: UUID, val offset: Long, val data: ByteArray)

fun decodeChunk(data: ByteArray): DecodedChunk? {
    if (data.size <= CHUNK_HEADER_SIZE) return null
    val buf = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
    val id = UUID(buf.long, buf.long)
    val offset = buf.long
    return DecodedChunk(id, offset, data.copyOfRange(CHUNK_HEADER_SIZE, data.size))
}

/** Накопитель принимаемого файла (пишет куски последовательно). */
class FileAssembly(
    val name: String,
    val size: Long,
    private val out: OutputStream,
    private val onComplete: () -> Unit = {},
) {
    var received = 0L
        private set
    val isComplete: Boolean get() = received >= size

    fun write(data: ByteArray) {
        out.write(data)
        received += data.size
    }

    fun close() {
        runCatching { out.close() }
        runCatching { onComplete() }
    }
}

/** Отправка файла с Pixel на Mac из системного «Поделиться». */
object FileSender {
    fun send(context: Context, uri: Uri, client: WebSocketClient, local: DeviceInfo?) {
        val resolver = context.contentResolver
        val name = queryColumn(resolver, uri, OpenableColumns.DISPLAY_NAME)
            ?: uri.lastPathSegment?.substringAfterLast('/')
            ?: "file"
        val sizeFromQuery = queryColumn(resolver, uri, OpenableColumns.SIZE)?.toLongOrNull()
        val sizeFromFd = runCatching { resolver.openFileDescriptor(uri, "r")?.use { it.statSize } }.getOrNull()
        val sizeFromFile =
            if (uri.scheme == "file") runCatching { File(uri.path ?: "").length() }.getOrDefault(0L) else 0L
        val size = (sizeFromQuery ?: sizeFromFd ?: sizeFromFile).coerceAtLeast(0L)
        val mime = resolver.getType(uri) ?: "application/octet-stream"
        val id = UUID.randomUUID()

        client.send(Message(type = MessageType.FILE_META, device = local, file = FileMetaPayload(
            id = id.toString(), name = name, size = size, mime = mime,
        )))

        resolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(64 * 1024)
            var offset = 0L
            while (true) {
                val n = input.read(buffer)
                if (n <= 0) break
                client.sendBinary(encodeChunk(id, offset, buffer.copyOf(n)))
                offset += n
            }
        }
    }

    private fun queryColumn(r: ContentResolver, uri: Uri, column: String): String? =
        r.query(uri, arrayOf(column), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
}

/** Поток записи + пост-действие (для MediaStore IS_PENDING). */
class IncomingSink(val stream: OutputStream, val onComplete: () -> Unit)

/**
 * Куда принять файл: изображения (mime image/…) — в «Фото» (MediaStore.Images) на Android 10+,
 * остальное — в «Загрузки/IGoogle».
 */
fun openIncomingSink(context: Context, name: String, mime: String): IncomingSink? {
    val isImage = mime.startsWith("image/")
    if (isImage && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, mime)
            put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/IGoogle")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return null
        val stream = context.contentResolver.openOutputStream(uri) ?: return null
        val done = {
            val clear = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
            runCatching { context.contentResolver.update(uri, clear, null, null) }
            Unit
        }
        return IncomingSink(stream, done)
    }
    val out = openDownloadStream(context, name) ?: return null
    return IncomingSink(out, {})
}

/** Открывает поток записи в Downloads/IGoogle с учётом scoped storage. */
fun openDownloadStream(context: Context, name: String): OutputStream? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/IGoogle")
        }
        val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        uri?.let { context.contentResolver.openOutputStream(it) }
    } else {
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "IGoogle")
        dir.mkdirs()
        FileOutputStream(uniqueFile(dir, name))
    }
}

private fun uniqueFile(dir: File, name: String): File {
    val dot = name.lastIndexOf('.')
    val base = if (dot > 0) name.substring(0, dot) else name
    val ext = if (dot > 0) name.substring(dot) else ""
    var candidate = File(dir, name)
    var i = 1
    while (candidate.exists()) {
        candidate = File(dir, "$base ($i)$ext")
        i++
    }
    return candidate
}
