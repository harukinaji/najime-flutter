package com.naji.najimessenger

import android.content.Context
import android.util.Log
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject
import java.util.concurrent.Executors

object NajiReplySender {
    private const val TAG = "NajiFCM"

    fun sendReply(context: Context, chatId: String, text: String) {
        Executors.newSingleThreadExecutor().execute {
            try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val baseUrl = prefs.getString("flutter.native_base_url", null) ?: "https://najime.org:5000"
                val encryptedToken = prefs.getString("flutter.native_auth_token", null)
                val token = encryptedToken?.let { TokenCrypto.decrypt(it) }

                if (token.isNullOrEmpty()) {
                    Log.e(TAG, "No auth token found in SharedPreferences")
                    return@execute
                }

                val url = URL("$baseUrl/api/chats/$chatId/messages")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Authorization", "Bearer $token")
                conn.doOutput = true
                conn.connectTimeout = 10000
                conn.readTimeout = 10000

                val body = JSONObject().apply {
                    put("content", text)
                    put("type", "text")
                }

                OutputStreamWriter(conn.outputStream).use { it.write(body.toString()) }

                val code = conn.responseCode
                if (code !in 200..299) {
                    Log.e(TAG, "Reply failed: HTTP $code")
                }
                conn.disconnect()
            } catch (e: Exception) {
                Log.e(TAG, "Reply send error: ${e.message}", e)
            }
        }
    }
}
