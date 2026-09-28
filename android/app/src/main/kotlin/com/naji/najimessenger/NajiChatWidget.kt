package com.naji.najimessenger

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import android.widget.RemoteViews
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.os.Build
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

class NajiChatWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        scheduleRefresh(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        cancelRefresh(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, NajiChatWidget::class.java)
            )
            for (id in ids) {
                updateAppWidget(context, mgr, id)
            }
        }
    }

    companion object {
        private const val TAG = "NajiChatWidget"
        const val ACTION_REFRESH = "com.naji.najimessenger.WIDGET_REFRESH"
        private const val JOB_ID = 1001
        private const val PREFS_NAME = "naji_widget_chats"
        private const val KEY_NAMES = "chat_names"
        private const val KEY_MESSAGES = "chat_messages"
        private const val KEY_UNREAD = "chat_unreads"
        private const val KEY_COUNT = "chat_count"
        private const val KEY_TIMESTAMPS = "chat_timestamps"
        private const val KEY_ONLINE = "chat_online"
        private const val KEY_AVATARS = "chat_avatars"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            try {
                val views = RemoteViews(context.packageName, R.layout.widget_najime)

                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val count = prefs.getInt(KEY_COUNT, 0)

                val names = parseJsonList(prefs.getString(KEY_NAMES, "[]"))
                val messages = parseJsonList(prefs.getString(KEY_MESSAGES, "[]"))
                val unreads = parseJsonList(prefs.getString(KEY_UNREAD, "[]"))
                val timestamps = parseJsonList(prefs.getString(KEY_TIMESTAMPS, "[]"))
                val onlineStatuses = parseJsonBoolList(prefs.getString(KEY_ONLINE, "[]"))
                val avatarPaths = parseJsonList(prefs.getString(KEY_AVATARS, "[]"))

                Log.d(TAG, "updateAppWidget id=$appWidgetId count=$count")

                views.removeAllViews(R.id.widget_chat_list)

                if (count == 0) {
                    views.setTextViewText(R.id.widget_title, "NajiMe")
                    views.setTextViewText(R.id.widget_subtitle, "Нет активных чатов")
                } else {
                    val displayCount = minOf(count, 4)
                    views.setTextViewText(R.id.widget_title, "NajiMe")
                    views.setTextViewText(
                        R.id.widget_subtitle,
                        "$displayCount ${pluralize(displayCount, "чат", "чата", "чатов")}"
                    )

                    for (i in 0 until displayCount) {
                        val item = RemoteViews(context.packageName, R.layout.widget_chat_item)
                        val name = names.getOrElse(i) { "" }
                        val firstTwo = name.take(2).uppercase().ifEmpty { "?" }
                        item.setTextViewText(R.id.item_avatar, firstTwo)
                        item.setInt(R.id.item_avatar, "setBackgroundResource", getAvatarDrawable(name))
                        item.setTextViewText(R.id.item_name, name)
                        item.setTextViewText(R.id.item_message, messages.getOrElse(i) { "" })

                        val avatarPath = avatarPaths.getOrElse(i) { "" }
                        val avatarFile = if (avatarPath.isNotEmpty()) File(avatarPath) else null
                        if (avatarFile != null && avatarFile.exists() && avatarFile.length() > 0) {
                            val bitmap = decodeSampledBitmap(avatarFile, 84, 84)
                            if (bitmap != null) {
                                item.setImageViewBitmap(R.id.item_avatar_image, bitmap)
                                item.setViewVisibility(R.id.item_avatar_image, android.view.View.VISIBLE)
                                item.setViewVisibility(R.id.item_avatar, android.view.View.GONE)
                            } else {
                                item.setViewVisibility(R.id.item_avatar_image, android.view.View.GONE)
                                item.setViewVisibility(R.id.item_avatar, android.view.View.VISIBLE)
                            }
                        } else {
                            item.setViewVisibility(R.id.item_avatar_image, android.view.View.GONE)
                            item.setViewVisibility(R.id.item_avatar, android.view.View.VISIBLE)
                        }

                        val timestamp = timestamps.getOrElse(i) { "" }
                        val timeText = formatRelativeTime(timestamp)
                        if (timeText.isNotEmpty()) {
                            item.setTextViewText(R.id.item_time, timeText)
                            item.setViewVisibility(R.id.item_time, android.view.View.VISIBLE)
                        } else {
                            item.setViewVisibility(R.id.item_time, android.view.View.GONE)
                        }

                        val isOnline = onlineStatuses.getOrElse(i) { false }
                        item.setViewVisibility(
                            R.id.item_online_dot,
                            if (isOnline) android.view.View.VISIBLE else android.view.View.GONE
                        )

                        val unread = unreads.getOrElse(i) { "0" }.toIntOrNull() ?: 0
                        if (unread > 0) {
                            item.setTextViewText(R.id.item_unread, unread.toString())
                            item.setViewVisibility(R.id.item_unread, android.view.View.VISIBLE)
                        } else {
                            item.setViewVisibility(R.id.item_unread, android.view.View.GONE)
                        }

                        views.addView(R.id.widget_chat_list, item)
                    }
                }

                val openIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_MAIN
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val pendingIntent = PendingIntent.getActivity(
                    context, 0, openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                val refreshIntent = Intent(context, NajiChatWidget::class.java).apply {
                    action = ACTION_REFRESH
                }
                val refreshPending = PendingIntent.getBroadcast(
                    context, 1, refreshIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_refresh_btn, refreshPending)

                appWidgetManager.updateAppWidget(appWidgetId, views)
                Log.d(TAG, "updateAppWidget id=$appWidgetId SUCCESS")
            } catch (e: Exception) {
                Log.e(TAG, "updateAppWidget FAILED for id=$appWidgetId", e)
            }
        }

        fun updateFromFlutter(
            context: Context,
            names: List<String>,
            messages: List<String>,
            unreads: List<String>,
            timestamps: List<String>,
            onlineStatuses: List<Boolean>,
            avatarPaths: List<String>
        ) {
            Log.d(TAG, "updateFromFlutter: ${names.size} chats, ${avatarPaths.size} avatars")
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().apply {
                putInt(KEY_COUNT, names.size)
                putString(KEY_NAMES, org.json.JSONArray(names).toString())
                putString(KEY_MESSAGES, org.json.JSONArray(messages).toString())
                putString(KEY_UNREAD, org.json.JSONArray(unreads).toString())
                putString(KEY_TIMESTAMPS, org.json.JSONArray(timestamps).toString())
                val onlineArray = org.json.JSONArray()
                onlineStatuses.forEach { onlineArray.put(it) }
                putString(KEY_ONLINE, onlineArray.toString())
                putString(KEY_AVATARS, org.json.JSONArray(avatarPaths).toString())
                apply()
            }

            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, NajiChatWidget::class.java)
            )
            for (id in ids) {
                updateAppWidget(context, mgr, id)
            }
        }

        private fun decodeSampledBitmap(file: File, reqWidth: Int, reqHeight: Int): Bitmap? {
            return try {
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.absolutePath, options)
                options.inSampleSize = calculateInSampleSize(options, reqWidth, reqHeight)
                options.inJustDecodeBounds = false
                BitmapFactory.decodeFile(file.absolutePath, options)
            } catch (e: Exception) {
                Log.e(TAG, "decodeSampledBitmap failed: ${file.absolutePath}", e)
                null
            }
        }

        private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
            val height = options.outHeight
            val width = options.outWidth
            var inSampleSize = 1
            if (height > reqHeight || width > reqWidth) {
                val halfHeight = height / 2
                val halfWidth = width / 2
                while (halfHeight / inSampleSize >= reqHeight && halfWidth / inSampleSize >= reqWidth) {
                    inSampleSize *= 2
                }
            }
            return inSampleSize
        }

        private fun parseJsonList(json: String?): List<String> {
            if (json.isNullOrEmpty() || json == "[]") return emptyList()
            return try {
                val arr = org.json.JSONArray(json)
                (0 until arr.length()).map { arr.getString(it) }
            } catch (e: Exception) {
                Log.e(TAG, "parseJsonList failed: $json", e)
                emptyList()
            }
        }

        private fun parseJsonBoolList(json: String?): List<Boolean> {
            if (json.isNullOrEmpty() || json == "[]") return emptyList()
            return try {
                val arr = org.json.JSONArray(json)
                (0 until arr.length()).map { arr.optBoolean(it, false) }
            } catch (e: Exception) {
                emptyList()
            }
        }

        private fun formatRelativeTime(isoTimestamp: String): String {
            if (isoTimestamp.isEmpty()) return ""
            return try {
                val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())
                val date = sdf.parse(isoTimestamp) ?: return ""
                val now = Date()
                val diffMs = now.time - date.time

                when {
                    diffMs < TimeUnit.MINUTES.toMillis(1) -> "сейчас"
                    diffMs < TimeUnit.HOURS.toMillis(1) -> {
                        val mins = TimeUnit.MILLISECONDS.toMinutes(diffMs).toInt()
                        "$mins мин"
                    }
                    diffMs < TimeUnit.DAYS.toMillis(1) -> {
                        val hours = TimeUnit.MILLISECONDS.toHours(diffMs).toInt()
                        "$hours ч"
                    }
                    diffMs < TimeUnit.DAYS.toMillis(2) -> "вчера"
                    diffMs < TimeUnit.DAYS.toMillis(7) -> {
                        val cal = Calendar.getInstance().apply { time = date }
                        val dayNames = arrayOf("вс", "пн", "вт", "ср", "чт", "пт", "сб")
                        dayNames[cal.get(Calendar.DAY_OF_WEEK) - 1]
                    }
                    else -> {
                        val dayFmt = SimpleDateFormat("d.MM", Locale.getDefault())
                        dayFmt.format(date)
                    }
                }
            } catch (e: Exception) {
                ""
            }
        }

        private val AVATAR_DRAWABLES = intArrayOf(
            R.drawable.widget_avatar_0,
            R.drawable.widget_avatar_1,
            R.drawable.widget_avatar_2,
            R.drawable.widget_avatar_3,
            R.drawable.widget_avatar_4,
            R.drawable.widget_avatar_5,
            R.drawable.widget_avatar_6,
            R.drawable.widget_avatar_7,
            R.drawable.widget_avatar_8,
            R.drawable.widget_avatar_9,
            R.drawable.widget_avatar_10,
            R.drawable.widget_avatar_11,
        )

        private fun getAvatarDrawable(name: String): Int {
            val index = name.hashCode().let { if (it < 0) -it else it } % AVATAR_DRAWABLES.size
            return AVATAR_DRAWABLES[index]
        }

        private fun scheduleRefresh(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val job = JobInfo.Builder(
                    JOB_ID,
                    ComponentName(context, WidgetRefreshJob::class.java)
                ).setPeriodic(30 * 60 * 1000L)
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                    .build()
                val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
                scheduler.schedule(job)
            }
        }

        private fun cancelRefresh(context: Context) {
            val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            scheduler.cancel(JOB_ID)
        }

        private fun pluralize(n: Int, one: String, few: String, many: String): String {
            val mod10 = n % 10
            val mod100 = n % 100
            return when {
                mod10 == 1 && mod100 != 11 -> one
                mod10 in 2..4 && mod100 !in 12..14 -> few
                else -> many
            }
        }
    }
}
