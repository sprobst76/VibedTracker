package com.vibedtracker.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Startet die App automatisch nach einem Geräte-Neustart,
 * damit das Geofencing und Zeittracking sofort wieder aktiv ist.
 *
 * WorkManager-Tasks (periodischer Hintergrund-Sync) überleben Neustarts
 * automatisch – sie werden vom System neu eingeplant, sobald WorkManager
 * initialisiert wurde. Dieser Receiver startet zusätzlich die MainActivity,
 * damit der Flutter-Code läuft und der Geofence-Service neu gestartet wird.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {
            Log.d("BootReceiver", "Device booted - starting VibedTracker")

            // MainActivity starten: initialisiert Flutter, WorkManager und GeofenceService.
            // Auf Android 10+ kann startActivity im Hintergrund fehlschlagen –
            // WorkManager übernimmt dann die Hintergrundarbeit ohne sichtbare UI.
            try {
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    putExtra("boot_restart", true)
                }
                context.startActivity(launchIntent)
                Log.d("BootReceiver", "MainActivity launched")
            } catch (e: Exception) {
                Log.w("BootReceiver", "Could not start MainActivity: ${e.message}")
            }
        }
    }
}
