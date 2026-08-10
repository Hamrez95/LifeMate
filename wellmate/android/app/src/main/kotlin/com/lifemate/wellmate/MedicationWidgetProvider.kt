package com.lifemate.wellmate

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import kotlin.math.max

class MedicationWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(
                context.packageName,
                R.layout.wellmate_medication_widget,
            )
            bindWidget(context, views, widgetData)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun bindWidget(
        context: Context,
        views: RemoteViews,
        data: SharedPreferences,
    ) {
        val hasData = data.getBoolean(HAS_DATA, false)
        val openApp = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("wellmate-widget://open"),
        )
        views.setOnClickPendingIntent(R.id.widget_root, openApp)
        views.setOnClickPendingIntent(R.id.widget_empty_content, openApp)

        if (!hasData) {
            views.setViewVisibility(R.id.widget_content, View.GONE)
            views.setViewVisibility(R.id.widget_empty_content, View.VISIBLE)
            return
        }

        views.setViewVisibility(R.id.widget_content, View.VISIBLE)
        views.setViewVisibility(R.id.widget_empty_content, View.GONE)

        val treatmentName = data.getString(TREATMENT_NAME, null).orDash()
        val description = data.getString(DESCRIPTION, null).orDash()
        val dose = data.getString(DOSE, null).orDash()
        val quantity = data.getString(QUANTITY, null).orDash()
        val time = data.getString(TIME, null).orDash()
        val occurrenceId = data.getString(OCCURRENCE_ID, null).orEmpty()
        val version = readLong(data, VERSION, 1L).toInt()
        val scheduledAtEpochMs = readLong(data, SCHEDULED_AT, 0L)
        val overdue =
            data.getBoolean(OVERDUE, false) ||
                (scheduledAtEpochMs > 0L && scheduledAtEpochMs <= System.currentTimeMillis())
        val actionMessage = data.getString(ACTION_MESSAGE, null).orEmpty()

        views.setTextViewText(R.id.widget_treatment_name, treatmentName)
        views.setTextViewText(R.id.widget_description, description)
        views.setTextViewText(R.id.widget_dose, dose)
        views.setTextViewText(R.id.widget_quantity, quantity)
        views.setTextViewText(R.id.widget_time, time)
        views.setTextViewText(
            R.id.widget_action_text,
            if (actionMessage.isEmpty()) "مصرف کردم" else actionMessage,
        )

        if (overdue || scheduledAtEpochMs <= 0L) {
            views.setViewVisibility(R.id.widget_countdown, View.GONE)
            views.setViewVisibility(R.id.widget_countdown_static, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_countdown_static,
                if (scheduledAtEpochMs <= 0L) "—" else "گذشته",
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val remainingMs = max(
                0L,
                scheduledAtEpochMs - System.currentTimeMillis(),
            )
            views.setViewVisibility(R.id.widget_countdown_static, View.GONE)
            views.setViewVisibility(R.id.widget_countdown, View.VISIBLE)
            views.setChronometer(
                R.id.widget_countdown,
                SystemClock.elapsedRealtime() + remainingMs,
                null,
                true,
            )
        } else {
            views.setViewVisibility(R.id.widget_countdown, View.GONE)
            views.setViewVisibility(R.id.widget_countdown_static, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_countdown_static,
                formatRemainingPersian(scheduledAtEpochMs),
            )
        }

        if (occurrenceId.isNotEmpty()) {
            val takenUri = Uri.Builder()
                .scheme("wellmate-widget")
                .authority("taken")
                .appendQueryParameter("id", occurrenceId)
                .appendQueryParameter("version", version.toString())
                .build()
            val takenIntent = HomeWidgetBackgroundIntent.getBroadcast(
                context,
                takenUri,
            )
            views.setOnClickPendingIntent(R.id.widget_take_button, takenIntent)
        } else {
            views.setOnClickPendingIntent(R.id.widget_take_button, openApp)
        }

        views.setContentDescription(
            R.id.widget_take_button,
            "ثبت مصرف $treatmentName",
        )
    }

    private fun readLong(
        data: SharedPreferences,
        key: String,
        fallback: Long,
    ): Long {
        return when (val value = data.all[key]) {
            is Long -> value
            is Int -> value.toLong()
            is String -> value.toLongOrNull() ?: fallback
            else -> fallback
        }
    }

    private fun formatRemainingPersian(targetEpochMs: Long): String {
        val remainingSeconds = max(
            0L,
            (targetEpochMs - System.currentTimeMillis()) / 1000L,
        )
        val hours = remainingSeconds / 3600L
        val minutes = (remainingSeconds % 3600L) / 60L
        return persianDigits(
            String.format("%02d:%02d", hours, minutes),
        )
    }

    private fun persianDigits(value: String): String {
        val western = "0123456789"
        val persian = "۰۱۲۳۴۵۶۷۸۹"
        return buildString(value.length) {
            value.forEach { character ->
                val index = western.indexOf(character)
                append(if (index < 0) character else persian[index])
            }
        }
    }

    private fun String?.orDash(): String =
        if (this.isNullOrBlank()) "—" else this

    companion object {
        private const val HAS_DATA = "wm_widget_has_data"
        private const val OCCURRENCE_ID = "wm_widget_occurrence_id"
        private const val VERSION = "wm_widget_version"
        private const val TREATMENT_NAME = "wm_widget_treatment_name"
        private const val DESCRIPTION = "wm_widget_description"
        private const val DOSE = "wm_widget_dose"
        private const val QUANTITY = "wm_widget_quantity"
        private const val TIME = "wm_widget_time"
        private const val SCHEDULED_AT = "wm_widget_scheduled_at_epoch_ms"
        private const val OVERDUE = "wm_widget_overdue"
        private const val ACTION_MESSAGE = "wm_widget_action_message"
    }
}
