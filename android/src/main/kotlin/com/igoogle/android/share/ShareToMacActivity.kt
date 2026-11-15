package com.igoogle.android.share

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import com.igoogle.android.FileSender
import com.igoogle.android.MacLink
import com.igoogle.shared.ClipboardPayload
import com.igoogle.shared.Message
import com.igoogle.shared.MessageType

/**
 * Обрабатывает системное «Поделиться»: пункт «Отправить на MacBook».
 * Поддерживает текст (буфер обмена) и файлы (бинарные кадры).
 */
class ShareToMacActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val client = MacLink.client
        val text = extractText(intent)
        val stream = extractStream(intent)
        Log.d(TAG, "share: client=${client != null} text=$text stream=$stream")

        if (client == null) {
            Toast.makeText(this, "MacBook не найден. Запустите IGoogle на Mac", Toast.LENGTH_LONG).show()
            finish()
            return
        }

        when {
            text != null -> {
                client.send(Message(
                    type = MessageType.CLIPBOARD,
                    device = MacLink.local,
                    clipboard = ClipboardPayload(text = text),
                ))
                Log.d(TAG, "share: sent text to Mac")
                Toast.makeText(this, "Отправлено на MacBook", Toast.LENGTH_SHORT).show()
            }

            stream != null -> {
                val local = MacLink.local
                Toast.makeText(this, "Отправляю файл…", Toast.LENGTH_SHORT).show()
                Thread {
                    runCatching { FileSender.send(applicationContext, stream, client, local) }
                        .onFailure { Log.d(TAG, "share file error: ${it.message}") }
                }.start()
            }

            else ->
                Toast.makeText(this, "Этот тип содержимого пока не поддерживается", Toast.LENGTH_LONG).show()
        }

        finish()
    }

    private fun extractText(intent: Intent?): String? =
        if (intent?.type == "text/plain") intent.getStringExtra(Intent.EXTRA_TEXT) else null

    private fun extractStream(intent: Intent?): Uri? =
        intent?.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri

    private companion object {
        const val TAG = "IGoogle"
    }
}
