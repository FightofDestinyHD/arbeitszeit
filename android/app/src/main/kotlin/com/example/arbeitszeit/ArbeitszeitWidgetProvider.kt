package com.example.arbeitszeit

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class ArbeitszeitWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val launchIntent = Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.arbeitszeit_widget)
            val todayDuration = widgetData.getString("today_duration", "0h 0m") ?: "0h 0m"
            val remainingDuration = widgetData.getString("remaining_duration", "0h 0m") ?: "0h 0m"
            val monthBalance = widgetData.getString("month_balance", "0h 0m") ?: "0h 0m"
            val isWorking = widgetData.getBoolean("is_working", false)
            val isPaused = widgetData.getBoolean("is_paused", false)
            val actionLabel = widgetData.getString("action_label", "Start") ?: "Start"
            val activeStartMillis = widgetData.getString("active_start_millis", null)?.toLongOrNull()
            val statusText = when {
                isPaused -> "Pause läuft"
                isWorking -> "Arbeitszeit läuft"
                else -> "Nicht eingestempelt"
            }

            val widgetAction = when {
                isPaused -> "arbeitszeit://resume"
                isWorking -> "arbeitszeit://pause"
                else -> "arbeitszeit://start"
            }

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                action = "es.antonborri.home_widget.action.LAUNCH"
                data = Uri.parse(widgetAction)
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                widgetAction.hashCode(),
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            views.setTextViewText(R.id.widget_status, statusText)
            views.setTextViewText(R.id.widget_today_value, todayDuration)
            views.setTextViewText(R.id.widget_remaining_value, remainingDuration)
            views.setTextViewText(R.id.widget_balance_value, monthBalance)
            views.setTextViewText(R.id.widget_action_button, actionLabel)
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            views.setOnClickPendingIntent(R.id.widget_action_button, pendingIntent)

            if (isWorking && activeStartMillis != null) {
                val base = SystemClock.elapsedRealtime() - (System.currentTimeMillis() - activeStartMillis)
                views.setViewVisibility(R.id.widget_chronometer, View.VISIBLE)
                views.setChronometer(R.id.widget_chronometer, base, null, true)
            } else {
                views.setViewVisibility(R.id.widget_chronometer, View.GONE)
                views.setChronometer(R.id.widget_chronometer, SystemClock.elapsedRealtime(), null, false)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}