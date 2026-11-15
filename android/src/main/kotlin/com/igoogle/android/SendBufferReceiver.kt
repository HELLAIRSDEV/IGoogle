package com.igoogle.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast
import com.igoogle.shared.ClipboardPayload
import com.igoogle.shared.Message
import com.igoogle.shared.MessageType

/** Действие из уведомления: отправить последний буфер на Mac без открытия приложения. */
class SendBufferReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val client = MacLink.client
        val text = MacLink.lastClipboard
        if (client != null && text != null) {
            client.send(Message(
                type = MessageType.CLIPBOARD,
                device = MacLink.local,
                clipboard = ClipboardPayload(text = text),
            ))
            Toast.makeText(context, "Отправлено на MacBook", Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(context, "MacBook не подключён", Toast.LENGTH_SHORT).show()
        }
    }
}
