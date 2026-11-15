package com.igoogle.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/** Уведомление-статус + «Отправить буфер» (ambient-доступ и foreground-service). */
object NotificationHelper {
    const val CHANNEL_ID = "igoogle_status"
    const val NOTIF_ID = 42

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(CHANNEL_ID, "IGoogle", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Статус подключения к Mac"
            }
            mgr.createNotificationChannel(channel)
        }
    }

    fun build(context: Context, text: String): Notification {
        ensureChannel(context)

        val sendPi = PendingIntent.getBroadcast(
            context, 0, Intent(context, SendBufferReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val openPi = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(context, 1, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_tile)
            .setContentTitle("IGoogle")
            .setContentText(text)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(0, "Отправить буфер", sendPi)
        if (openPi != null) builder.setContentIntent(openPi)
        return builder.build()
    }

    fun showConnected(context: Context, macName: String?) {
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.notify(NOTIF_ID, build(context, macName ?: "MacBook"))
    }

    fun clear(context: Context) {
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.cancel(NOTIF_ID)
    }
}
