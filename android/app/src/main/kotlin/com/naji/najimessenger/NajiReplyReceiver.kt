package com.naji.najimessenger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class NajiReplyReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "NajiFCM"
        const val EXTRA_CHAT_ID = "chat_id"
        const val EXTRA_REPLY_TEXT = "reply_text"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val chatId = intent.getStringExtra(EXTRA_CHAT_ID) ?: return
        val replyText = NajiPushNotificationHelper.getReplyText(intent) ?: return

        Log.d(TAG, "Reply received: chatId=$chatId text=$replyText")
        NajiReplySender.sendReply(context, chatId, replyText)
    }
}
