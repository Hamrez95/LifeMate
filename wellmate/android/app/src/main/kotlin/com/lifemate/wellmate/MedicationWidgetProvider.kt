package com.lifemate.wellmate

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.view.Gravity
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
        val isPersian = data.getString(LANGUAGE_CODE, "fa")?.lowercase() != "en"
        bindLocale(views, isPersian)

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

        val treatmentName = localizeDigits(data.getString(TREATMENT_NAME, null).orDash(), isPersian)
        val description = localizeDigits(data.getString(DESCRIPTION, null).orDash(), isPersian)
        val dose = localizeDigits(data.getString(DOSE, null).orDash(), isPersian)
        val quantity = localizeDigits(data.getString(QUANTITY, null).orDash(), isPersian)
        val time = localizeDigits(data.getString(TIME, null).orDash(), isPersian)
        val occurrenceId = data.getString(OCCURRENCE_ID, null).orEmpty()
        val version = readLong(data, VERSION, 1L).toInt()
        val scheduledAtEpochMs = readLong(data, SCHEDULED_AT, 0L)
        val overdue =
            data.getBoolean(OVERDUE, false) ||
                (scheduledAtEpochMs > 0L && scheduledAtEpochMs <= System.currentTimeMillis())
        val actionMessage = localizeDigits(data.getString(ACTION_MESSAGE, null).orEmpty(), isPersian)

        views.setTextViewText(R.id.widget_treatment_name, treatmentName)
        views.setTextViewText(R.id.widget_description, description)
        views.setTextViewText(R.id.widget_dose, dose)
        views.setTextViewText(R.id.widget_quantity, quantity)
        views.setTextViewText(R.id.widget_time, time)
        views.setTextViewText(
            R.id.widget_action_text,
            if (actionMessage.isEmpty()) copy(isPersian, "مصرف کردم", "Taken") else actionMessage,
        )

        if (overdue || scheduledAtEpochMs <= 0L) {
            views.setViewVisibility(R.id.widget_countdown_en, View.GONE)
            views.setViewVisibility(R.id.widget_countdown_fa, View.GONE)
            views.setViewVisibility(R.id.widget_countdown_static, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_countdown_static,
                if (scheduledAtEpochMs <= 0L) "—" else copy(isPersian, "زمان مصرف گذشته", "Dose time passed"),
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val remainingMs = max(
                0L,
                scheduledAtEpochMs - System.currentTimeMillis(),
            )
            views.setViewVisibility(R.id.widget_countdown_static, View.GONE)
            val chronometerId = if (isPersian) R.id.widget_countdown_fa else R.id.widget_countdown_en
            val hiddenChronometerId = if (isPersian) R.id.widget_countdown_en else R.id.widget_countdown_fa
            views.setViewVisibility(hiddenChronometerId, View.GONE)
            views.setViewVisibility(chronometerId, View.VISIBLE)
            views.setChronometer(
                chronometerId,
                SystemClock.elapsedRealtime() + remainingMs,
                null,
                true,
            )
        } else {
            views.setViewVisibility(R.id.widget_countdown_en, View.GONE)
            views.setViewVisibility(R.id.widget_countdown_fa, View.GONE)
            views.setViewVisibility(R.id.widget_countdown_static, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_countdown_static,
                formatRemaining(scheduledAtEpochMs, isPersian),
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
            copy(isPersian, "ثبت مصرف $treatmentName", "Log $treatmentName as taken"),
        )
        views.setContentDescription(
            R.id.widget_capsule_art,
            copy(isPersian, "داروی بعدی $treatmentName", "Next medication: $treatmentName"),
        )
        views.setContentDescription(
            R.id.widget_alarm_art,
            if (overdue) {
                copy(isPersian, "زمان مصرف گذشته", "Dose time passed")
            } else {
                copy(isPersian, "زمان باقی‌مانده تا مصرف", "Time remaining until dose")
            },
        )
    }

    private fun bindLocale(views: RemoteViews, isPersian: Boolean) {
        val direction = if (isPersian) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
        val textGravity = if (isPersian) Gravity.END else Gravity.START
        val localeAwareLayouts = intArrayOf(
            R.id.widget_content,
            R.id.widget_info_panel,
            R.id.widget_info_column,
            R.id.widget_quantity_row,
            R.id.widget_dose_row,
            R.id.widget_countdown_panel,
            R.id.widget_time_row,
            R.id.widget_take_button,
            R.id.widget_empty_content,
        )
        localeAwareLayouts.forEach { id ->
            views.setInt(id, "setLayoutDirection", direction)
        }
        views.setInt(R.id.widget_next_label, "setGravity", textGravity)
        views.setInt(R.id.widget_treatment_name, "setGravity", textGravity)
        views.setInt(R.id.widget_description, "setGravity", textGravity)

        views.setTextViewText(R.id.widget_next_label, copy(isPersian, "داروی بعدی", "Next medication"))
        views.setTextViewText(R.id.widget_time_label, copy(isPersian, "زمان مصرف", "Dose time"))
        views.setTextViewText(R.id.widget_empty_title, copy(isPersian, "برنامه بعدی در راه است", "Your next treatment is on the way"))
        views.setTextViewText(
            R.id.widget_empty_subtitle,
            copy(
                isPersian,
                "برای دیدن برنامه درمان، WellMate را باز کنید.",
                "Open WellMate to view your treatment plan.",
            ),
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

    private fun formatRemaining(targetEpochMs: Long, isPersian: Boolean): String {
        val remainingSeconds = max(
            0L,
            (targetEpochMs - System.currentTimeMillis()) / 1000L,
        )
        val hours = remainingSeconds / 3600L
        val minutes = (remainingSeconds % 3600L) / 60L
        val seconds = remainingSeconds % 60L
        return localizeDigits(
            String.format("%02d:%02d:%02d", hours, minutes, seconds),
            isPersian,
        )
    }

    private fun localizeDigits(value: String, isPersian: Boolean): String {
        val latin = buildString(value.length) {
            value.forEach { character ->
                append(
                    when (character) {
                        in '۰'..'۹' -> ('0'.code + (character.code - '۰'.code)).toChar()
                        in '٠'..'٩' -> ('0'.code + (character.code - '٠'.code)).toChar()
                        else -> character
                    },
                )
            }
        }
        if (!isPersian) return latin
        val western = "0123456789"
        val persian = "۰۱۲۳۴۵۶۷۸۹"
        return buildString(latin.length) {
            latin.forEach { character ->
                val index = western.indexOf(character)
                append(if (index < 0) character else persian[index])
            }
        }
    }

    private fun copy(isPersian: Boolean, fa: String, en: String): String =
        if (isPersian) fa else en

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
        private const val LANGUAGE_CODE = "wm_widget_language_code"
    }
}
