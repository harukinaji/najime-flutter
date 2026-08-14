package com.naji.najimessenger

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import java.util.concurrent.atomic.AtomicInteger

class NajiPushNotificationHelper(
    private val context: Context,
    private val tag: String
) {
    companion object {
        const val CHANNEL_ID = "najime_messages"
        const val CHANNEL_NAME = "Messages"
        const val EXTRA_REPLY_TEXT = "reply_text"
        private val notificationCounter = AtomicInteger(0)

        fun getReplyText(intent: Intent): String? {
            val results = RemoteInput.getResultsFromIntent(intent)
            return results?.getCharSequence(EXTRA_REPLY_TEXT)?.toString()
        }
    }

    fun createNotificationChannels() {
        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Notifications for new messages"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 300, 200, 300)
            setSound(soundUri, audioAttributes)
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    fun showMessageNotification(title: String, message: String, data: Map<String, String>?) {
        val chatId = data?.get("chat_id") ?: return

        val contentIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("chat_id", chatId)
            putExtra("open_chat", true)
        }
        val contentPendingIntent = PendingIntent.getActivity(
            context,
            chatId.hashCode(),
            contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val replyRemoteInput = RemoteInput.Builder(EXTRA_REPLY_TEXT)
            .setLabel("Reply...")
            .build()

        val replyIntent = Intent(context, NajiReplyReceiver::class.java).apply {
            action = "com.naji.najimessenger.ACTION_REPLY"
            putExtra(NajiReplyReceiver.EXTRA_CHAT_ID, chatId)
        }
        val replyPendingIntent = PendingIntent.getBroadcast(
            context,
            chatId.hashCode() + 1,
            replyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        val replyAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_send,
            "Reply",
            replyPendingIntent
        )
            .addRemoteInput(replyRemoteInput)
            .setAllowGeneratedReplies(true)
            .build()

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(contentPendingIntent)
            .addAction(replyAction)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
            .build()

        val notifId = notificationCounter.incrementAndGet()
        try {
            NotificationManagerCompat.from(context).notify(notifId, notification)
            Log.d(tag, "Notification shown: id=$notifId title=$title")
        } catch (e: SecurityException) {
            Log.e(tag, "Notification permission not granted: $e")
        }
    }
}
