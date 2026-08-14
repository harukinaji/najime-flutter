package com.naji.najimessenger

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class NajiFirebaseMessagingService : FirebaseMessagingService() {
    companion object {
        private const val TAG = "NajiFCM"
    }

    private lateinit var pushHelper: NajiPushNotificationHelper

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created")
        pushHelper = NajiPushNotificationHelper(this, TAG)
        pushHelper.createNotificationChannels()
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "New FCM token: ${token.take(20)}...")
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        Log.d(TAG, "=== onMessageReceived START ===")

        val data = remoteMessage.data
        val notification = remoteMessage.notification

        var title = data["title"]
        var message = data["message"]

        if (title == null && notification != null) {
            title = notification.title
        }
        if (message == null && notification != null) {
            message = notification.body
        }

        if (title.isNullOrEmpty()) title = "NajiMe"
        if (message.isNullOrEmpty()) message = "New message"

        Log.d(TAG, "title=$title message=$message data=$data")
        pushHelper.showMessageNotification(title, message, data)
        Log.d(TAG, "=== onMessageReceived END ===")
    }
}
