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
            val activeStartMillis = widgetData.getString("active_start_millis", null)?.toLongOrNull()
            val statusText = when {
                isPaused -> "Pause läuft"
                isWorking -> "Arbeitszeit läuft"
                else -> "Nicht eingestempelt"
            }

            // Main button: Start oder Stop
            val mainAction = if (isWorking) "arbeitszeit://stop" else "arbeitszeit://start"
            val mainLabel = if (isWorking) "Stop" else "Start"
            val mainIntent = Intent(context, MainActivity::class.java).apply {
                action = "es.antonborri.home_widget.action.LAUNCH"
                data = Uri.parse(mainAction)
            }
            val mainPendingIntent = PendingIntent.getActivity(
                context,
                mainAction.hashCode(),
                mainIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            // Pause button: nur sichtbar wenn Schicht läuft
            val pauseAction = if (isPaused) "arbeitszeit://resume" else "arbeitszeit://pause"
            val pauseLabel = if (isPaused) "Weiter" else "Pause"
            val pauseIntent = Intent(context, MainActivity::class.java).apply {
                action = "es.antonborri.home_widget.action.LAUNCH"
                data = Uri.parse(pauseAction)
            }
            val pausePendingIntent = PendingIntent.getActivity(
                context,
                pauseAction.hashCode(),
                pauseIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            views.setTextViewText(R.id.widget_status, statusText)
            views.setTextViewText(R.id.widget_today_value, todayDuration)
            views.setTextViewText(R.id.widget_remaining_value, remainingDuration)
            views.setTextViewText(R.id.widget_balance_value, monthBalance)
            views.setTextViewText(R.id.widget_main_button, mainLabel)
            views.setOnClickPendingIntent(R.id.widget_main_button, mainPendingIntent)
            
            if (isWorking) {
                views.setViewVisibility(R.id.widget_pause_button, View.VISIBLE)
                views.setTextViewText(R.id.widget_pause_button, pauseLabel)
                views.setOnClickPendingIntent(R.id.widget_pause_button, pausePendingIntent)
            } else {
                views.setViewVisibility(R.id.widget_pause_button, View.GONE)
            }

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