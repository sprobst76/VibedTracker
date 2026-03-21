package com.vibedtracker.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.core.graphics.toColorInt

class WorkStatusWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            updateWidget(context, appWidgetManager, id)
        }
    }

    companion object {
        /** Called from MainActivity MethodChannel to refresh all placed widgets. */
        fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, WorkStatusWidget::class.java)
            )
            if (ids.isEmpty()) return

            for (id in ids) {
                updateWidget(context, manager, id)
            }
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            // shared_preferences Flutter plugin stores keys with "flutter." prefix
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )

            val status   = prefs.getString("flutter.widget_status",   "Inaktiv") ?: "Inaktiv"
            val duration = prefs.getString("flutter.widget_duration", "")         ?: ""
            val running  = prefs.getBoolean("flutter.widget_running", false)

            val bgColor = if (running) "#CC1B5E20".toColorInt() else "#CC1E1E2E".toColorInt()

            val views = RemoteViews(context.packageName, R.layout.work_status_widget)
            views.setTextViewText(R.id.tv_status, status)
            views.setTextViewText(R.id.tv_duration, duration)
            views.setInt(R.id.widget_root, "setBackgroundColor", bgColor)

            // Tap → open app
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            val pendingIntent = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
