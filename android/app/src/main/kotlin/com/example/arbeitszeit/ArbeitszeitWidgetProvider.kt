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

    private fun actionBroadcast(context: Context, uriString: String): PendingIntent {
        val intent = Intent(WidgetActionReceiver.ACTION_WIDGET).apply {
            setClass(context, WidgetActionReceiver::class.java)
            putExtra(WidgetActionReceiver.EXTRA_URI, uriString)
            // Jede URI braucht einen eindeutigen RequestCode damit PendingIntents nicht kollidieren
        }
        return PendingIntent.getBroadcast(
            context,
            uriString.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        // Tippen auf den Widget-Hintergrund/Titel öffnet die App
        val openAppIntent = Intent(context, MainActivity::class.java)
        val openAppPendingIntent = PendingIntent.getActivity(
            context,
            0,
            openAppIntent,
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

            // Titel öffnet App
            views.setOnClickPendingIntent(R.id.widget_root, openAppPendingIntent)

            // Start/Stop Button → Broadcast (öffnet App NICHT)
            val mainAction = if (isWorking) "arbeitszeit://stop" else "arbeitszeit://start"
            val mainLabel = if (isWorking) "Stop" else "Start"
            views.setTextViewText(R.id.widget_main_button, mainLabel)
            views.setOnClickPendingIntent(R.id.widget_main_button, actionBroadcast(context, mainAction))

            // Pause/Weiter Button → Broadcast (öffnet App NICHT)
            val pauseAction = if (isPaused) "arbeitszeit://resume" else "arbeitszeit://pause"
            val pauseLabel = if (isPaused) "Weiter" else "Pause"
            if (isWorking) {
                views.setViewVisibility(R.id.widget_pause_button, View.VISIBLE)
                views.setTextViewText(R.id.widget_pause_button, pauseLabel)
                views.setOnClickPendingIntent(R.id.widget_pause_button, actionBroadcast(context, pauseAction))
            } else {
                views.setViewVisibility(R.id.widget_pause_button, View.GONE)
            }

            views.setTextViewText(R.id.widget_status, statusText)
            views.setTextViewText(R.id.widget_today_value, todayDuration)
            views.setTextViewText(R.id.widget_remaining_value, remainingDuration)
            views.setTextViewText(R.id.widget_balance_value, monthBalance)

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