// lib/services/geofence_callback.dart
import 'dart:developer';
import 'package:geofence_foreground_service/geofence_foreground_service.dart';
import 'package:geofence_foreground_service/constants/geofence_event_type.dart';
import 'geofence_event_queue.dart';

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
          await GeofenceEventQueue.enqueue(GeofenceEventData(
            zoneId: zoneID,
            event: GeofenceEvent.enter,
            timestamp: timestamp,
          ));
        } else if (triggerType == GeofenceEventType.exit) {
          // Benutzer verlässt die Zone -> Arbeitszeit stoppen
          log('EXIT Zone: $zoneID - Queuing work stop event');
          await GeofenceEventQueue.enqueue(GeofenceEventData(
            zoneId: zoneID,
            event: GeofenceEvent.exit,
            timestamp: timestamp,
          ));
        }
      } catch (e) {
        log('Error queuing geofence event: $e', name: 'GeofenceCallback');
      }

      return true;
    },
  );
}
