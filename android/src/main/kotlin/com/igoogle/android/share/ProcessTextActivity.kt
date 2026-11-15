package com.igoogle.android.share

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import com.igoogle.android.MacLink
import com.igoogle.shared.ClipboardPayload
import com.igoogle.shared.Message
import com.igoogle.shared.MessageType

/**
 * Пункт «Поделиться на Mac» в меню выделения текста (ACTION_PROCESS_TEXT).
 * Появляется рядом с «Копировать / Вырезать / Вставить».
 */
class ProcessTextActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val text = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        val client = MacLink.client

        when {
            text.isNullOrEmpty() ->
                Toast.makeText(this, "Нет текста", Toast.LENGTH_SHORT).show()

            client == null ->
                Toast.makeText(this, "MacBook не найден. Откройте IGoogle", Toast.LENGTH_SHORT).show()

            else -> {
                client.send(Message(
                    type = MessageType.CLIPBOARD,
                    device = MacLink.local,
                    clipboard = ClipboardPayload(text = text),
                ))
                Toast.makeText(this, "Отправлено на MacBook", Toast.LENGTH_SHORT).show()
            }
        }

        finish()
    }
}
