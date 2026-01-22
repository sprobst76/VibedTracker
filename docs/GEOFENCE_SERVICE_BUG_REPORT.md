# Bug Report: NullPointerException in GeofenceForegroundService.onStartCommand

## Package
- **Name:** geofence_foreground_service
- **Version:** 1.1.5
- **Repository:** https://github.com/Basel-525k/geofence_foreground_service

## Issue Summary

When Android restarts the `GeofenceForegroundService` after it was killed due to memory pressure, the service crashes with a `NullPointerException` because the `intent` parameter in `onStartCommand` is null.

## Environment

- **Device:** Google Pixel (Android 14/15)
- **Flutter:** 3.x
- **Package Version:** 1.1.5

## Steps to Reproduce

1. Start the geofence service with `startGeofencingService()`
2. Register geofence zones
3. Put the app in background
4. Wait for Android to kill the service due to memory pressure (or use `adb shell am kill <package>`)
5. Observe the service crash when Android tries to restart it

## Expected Behavior

The service should handle null intents gracefully and either:
- Return `START_STICKY` to retry later
- Restore state from SharedPreferences and continue

## Actual Behavior

The service crashes with:

```
java.lang.RuntimeException: Unable to start service com.f2fk.geofence_foreground_service.GeofenceForegroundService@... with null

Caused by: java.lang.NullPointerException: Parameter specified as non-null is null: method com.f2fk.geofence_foreground_service.GeofenceForegroundService.onStartCommand, parameter intent
    at com.f2fk.geofence_foreground_service.GeofenceForegroundService.onStartCommand(Unknown Source:2)
```

After the crash, Android reschedules the restart with exponential backoff:
```
W ActivityManager: Rescheduling restart of crashed service ... in 2759775ms for mem-pressure-event
```

This means the service is offline for **46+ minutes** after each crash!

## Root Cause

In `GeofenceForegroundService.kt`, line 73:

```kotlin
override fun onStartCommand(intent: Intent, flags: Int, startId: Int): Int {
```

The `intent` parameter is declared as non-nullable (`Intent` instead of `Intent?`), but Android can pass `null` when restarting a service that uses `START_STICKY`.

From Android documentation:
> If your service returns START_STICKY, the system restarts it with a **null intent** (unless there are pending intents to deliver).

## Proposed Fix

Change the method signature to accept nullable intent and handle it gracefully:

```kotlin
override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    // Handle null intent (service restart after being killed)
    if (intent == null) {
        Log.w(TAG, "Service restarted with null intent - recovering from saved state")
        return recoverFromSavedState(flags, startId)
    }

    // Existing code...
    val geofenceAction: GeofenceServiceAction = GeofenceServiceAction.valueOf(
        intent.getStringExtra(
            applicationContext!!.extraNameGen(Constants.geofenceAction)
        )!!
    )
    // ...
}

private fun recoverFromSavedState(flags: Int, startId: Int): Int {
    // Option 1: Return START_STICKY to try again later
    // return START_STICKY

    // Option 2: Restore from SharedPreferences and restart foreground notification
    val prefs = getSharedPreferences("geofence_service_state", Context.MODE_PRIVATE)
    if (!prefs.getBoolean("is_running", false)) {
        stopSelf()
        return START_NOT_STICKY
    }

    val channelId = prefs.getString("channel_id", "default_channel")!!
    val contentTitle = prefs.getString("content_title", "Geofencing active")!!
    val contentText = prefs.getString("content_text", "Monitoring location")!!
    val serviceId = prefs.getInt("service_id", 525600)
    val appIcon = prefs.getInt("app_icon", android.R.drawable.ic_menu_mylocation)

    val notification = NotificationCompat.Builder(this, channelId)
        .setOngoing(true)
        .setSmallIcon(appIcon)
        .setContentTitle(contentTitle)
        .setContentText(contentText)
        .build()

    startForeground(serviceId, notification, FOREGROUND_SERVICE_TYPE_LOCATION)

    // Re-subscribe to location updates
    subscribeToLocationUpdates()

    return START_STICKY
}
```

Additionally, save the service state when starting:

```kotlin
private fun saveServiceState(channelId: String, contentTitle: String, contentText: String, serviceId: Int, appIcon: Int) {
    getSharedPreferences("geofence_service_state", Context.MODE_PRIVATE)
        .edit()
        .putString("channel_id", channelId)
        .putString("content_title", contentTitle)
        .putString("content_text", contentText)
        .putInt("service_id", serviceId)
        .putInt("app_icon", appIcon)
        .putBoolean("is_running", true)
        .apply()
}
```

## Workaround for Users

Until this is fixed, users can disable battery optimization for their app:

1. Go to **Settings → Apps → [Your App] → Battery**
2. Select **Unrestricted** or **Don't optimize**

This prevents Android from killing the service due to memory pressure.

## Impact

- **Severity:** High - Geofencing becomes unreliable
- **Affected users:** Anyone using the package on Android with memory pressure
- **User experience:** Geofence events are missed for 46+ minutes after each crash

## Related

- Android Service lifecycle documentation: https://developer.android.com/reference/android/app/Service#START_STICKY
- Similar issues in other packages handling foreground services

---

**Reported by:** VibedTracker App
**Date:** 2026-01-22
