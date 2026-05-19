package com.example.arbeitszeit

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class ArbeitszeitWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        // Tippen auf den Widget-Hintergrund/Titel öffnet die App
        val openAppPendingIntent = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
        )

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.arbeitszeit_widget)
            val todayDuration = widgetData.getString("today_duration", "0h 0m") ?: "0h 0m"
            val remainingDuration = widgetData.getString("remaining_duration", "0h 0m") ?: "0h 0m"
            val monthBalance = widgetData.getString("month_balance", "0h 0m") ?: "0h 0m"
            val todayBalance = widgetData.getString("today_balance", "0h 0m") ?: "0h 0m"
            val isWorking = widgetData.getBoolean("is_working", false)
            val isPaused = widgetData.getBoolean("is_paused", false)
            val activeStartMillis = widgetData.getString("active_start_millis", null)?.toLongOrNull()
            val pauseStartMillis = widgetData.getString("pause_start_millis", null)?.toLongOrNull()

            val statusText = when {
                isPaused -> "Pause läuft"
                isWorking -> "Arbeitszeit läuft"
                else -> "Nicht eingestempelt"
            }

            // Titel öffnet App
            views.setOnClickPendingIntent(R.id.widget_root, openAppPendingIntent)

            // Start/Stop Button → Background-Callback (öffnet App NICHT)
            val mainUri = if (isWorking) Uri.parse("arbeitszeit://stop") else Uri.parse("arbeitszeit://start")
            val mainLabel = if (isWorking) "Stop" else "Start"
            views.setTextViewText(R.id.widget_main_button, mainLabel)
            views.setOnClickPendingIntent(
                R.id.widget_main_button,
                HomeWidgetBackgroundIntent.getBroadcast(context, mainUri),
            )

            // Pause/Weiter Button → Background-Callback (öffnet App NICHT)
            if (isWorking) {
                val pauseUri = if (isPaused) Uri.parse("arbeitszeit://resume") else Uri.parse("arbeitszeit://pause")
                val pauseLabel = if (isPaused) "Weiter" else "Pause"
                views.setViewVisibility(R.id.widget_pause_button, View.VISIBLE)
                views.setTextViewText(R.id.widget_pause_button, pauseLabel)
                views.setOnClickPendingIntent(
                    R.id.widget_pause_button,
                    HomeWidgetBackgroundIntent.getBroadcast(context, pauseUri),
                )
            } else {
                views.setViewVisibility(R.id.widget_pause_button, View.GONE)
            }

            views.setTextViewText(R.id.widget_status, statusText)
            views.setTextViewText(R.id.widget_today_value, todayDuration)
            views.setTextViewText(R.id.widget_remaining_value, remainingDuration)
            views.setTextViewText(R.id.widget_today_balance_value, todayBalance)
            views.setTextViewText(R.id.widget_balance_value, monthBalance)

            if (isWorking && activeStartMillis != null) {
                val base = SystemClock.elapsedRealtime() - (System.currentTimeMillis() - activeStartMillis)
                views.setViewVisibility(R.id.widget_chronometer, View.VISIBLE)
                views.setChronometer(R.id.widget_chronometer, base, null, true)
            } else {
                views.setViewVisibility(R.id.widget_chronometer, View.GONE)
                views.setChronometer(R.id.widget_chronometer, SystemClock.elapsedRealtime(), null, false)
            }

            if (isPaused && pauseStartMillis != null) {
                val pauseBase = SystemClock.elapsedRealtime() - (System.currentTimeMillis() - pauseStartMillis)
                views.setViewVisibility(R.id.widget_pause_chronometer, View.VISIBLE)
                views.setChronometer(R.id.widget_pause_chronometer, pauseBase, null, true)
            } else {
                views.setViewVisibility(R.id.widget_pause_chronometer, View.GONE)
                views.setChronometer(R.id.widget_pause_chronometer, SystemClock.elapsedRealtime(), null, false)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}