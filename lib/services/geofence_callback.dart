// lib/services/geofence_callback.dart
import 'dart:developer';
import 'package:geofence_foreground_service/geofence_foreground_service.dart';
import 'package:geofence_foreground_service/constants/geofence_event_type.dart';
import 'geofence_event_queue.dart';
import 'background_notification_service.dart';

/// Callback-Dispatcher für Geofence-Events
/// Wird im Background-Isolate ausgeführt
@pragma('vm:entry-point')
void callbackDispatcher() async {
  GeofenceForegroundService().handleTrigger(
    backgroundTriggerHandler: (zoneID, triggerType) async {
      final timestamp = DateTime.now();
      log('Geofence Event: Zone=$zoneID, Type=$triggerType, Time=$timestamp');

      try {
        if (triggerType == GeofenceEventType.enter) {
          // Benutzer betritt die Zone -> Arbeitszeit starten
          log('ENTER Zone: $zoneID - Queuing work start event');
          final result = await GeofenceEventQueue.enqueue(GeofenceEventData(
            zoneId: zoneID,
            event: GeofenceEvent.enter,
            timestamp: timestamp,
          ));

          // Notification basierend auf Ergebnis
          if (result == GeofenceEventQueue.resultAdded) {
            await BackgroundNotificationService.showWorkStartedNotification(timestamp);
            log('ENTER: Event queued and notification shown');
          } else if (result == GeofenceEventQueue.resultBounce) {
            log('ENTER: Event ignored (bounce protection)');
          } else {
            log('ENTER: Event ignored (duplicate)');
          }
        } else if (triggerType == GeofenceEventType.exit) {
          // Benutzer verlässt die Zone -> Arbeitszeit stoppen
          log('EXIT Zone: $zoneID - Queuing work stop event');
          final result = await GeofenceEventQueue.enqueue(GeofenceEventData(
            zoneId: zoneID,
            event: GeofenceEvent.exit,
            timestamp: timestamp,
          ));

          // Notification basierend auf Ergebnis
          if (result == GeofenceEventQueue.resultAdded) {
            await BackgroundNotificationService.showWorkStoppedNotification(timestamp);
            log('EXIT: Event queued and notification shown');
          } else if (result == GeofenceEventQueue.resultBounce) {
            log('EXIT: Event ignored (bounce protection)');
          } else {
            log('EXIT: Event ignored (duplicate)');
          }
        }
      } catch (e) {
        log('Error in geofence callback: $e', name: 'GeofenceCallback');
      }

      return true;
    },
  );
}
