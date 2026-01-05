// lib/services/geofence_callback.dart
import 'dart:developer';
import 'package:geofence_foreground_service/geofence_foreground_service.dart';
import 'package:geofence_foreground_service/constants/geofence_event_type.dart';

@pragma('vm:entry-point')
void callbackDispatcher() async {
  GeofenceForegroundService().handleTrigger(
    backgroundTriggerHandler: (zoneID, triggerType) {
      log('Zone $zoneID: $triggerType');
      if (triggerType == GeofenceEventType.enter) {
        log('ENTER', name: 'triggerType');
      } else if (triggerType == GeofenceEventType.exit) {
        log('EXIT', name: 'triggerType');
      }
      return Future.value(true);
    },
  );
}
