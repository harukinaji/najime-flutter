package com.naji.najimessenger

import android.app.job.JobParameters
import android.app.job.JobService
import android.appwidget.AppWidgetManager
import android.content.ComponentName

class WidgetRefreshJob : JobService() {

    override fun onStartJob(params: JobParameters?): Boolean {
        val mgr = AppWidgetManager.getInstance(this)
        val ids = mgr.getAppWidgetIds(
            ComponentName(this, NajiChatWidget::class.java)
        )
        for (id in ids) {
            NajiChatWidget.updateAppWidget(this, mgr, id)
        }
        return false
    }

    override fun onStopJob(params: JobParameters?): Boolean = false
}
