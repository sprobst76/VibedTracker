import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Event-Typen für Geofence-Ereignisse
enum GeofenceEvent { enter, exit }

/// Ein einzelnes Geofence-Ereignis
class GeofenceEventData {
  final String zoneId;
  final GeofenceEvent event;
  final DateTime timestamp;
  final bool processed;

  GeofenceEventData({
    required this.zoneId,
    required this.event,
    required this.timestamp,
    this.processed = false,
  });

  Map<String, dynamic> toJson() => {
        'zoneId': zoneId,
        'event': event.name,
        'timestamp': timestamp.toIso8601String(),
        'processed': processed,
      };

  factory GeofenceEventData.fromJson(Map<String, dynamic> json) {
    return GeofenceEventData(
      zoneId: json['zoneId'] as String,
      event: GeofenceEvent.values.firstWhere((e) => e.name == json['event']),
      timestamp: DateTime.parse(json['timestamp'] as String),
      processed: json['processed'] as bool? ?? false,
    );
  }

  GeofenceEventData copyWith({bool? processed}) {
    return GeofenceEventData(
      zoneId: zoneId,
      event: event,
      timestamp: timestamp,
      processed: processed ?? this.processed,
    );
  }
}

/// Queue für Geofence-Events, die im Background gespeichert werden
/// Verwendet SharedPreferences, da diese auch in Isolates funktionieren
class GeofenceEventQueue {
  static const _queueKey = 'geofence_event_queue';
  static const _lastEventKey = 'geofence_last_event';

  /// Fügt ein Event zur Queue hinzu (aus Background Isolate aufrufbar)
  static Future<void> enqueue(GeofenceEventData event) async {
    final prefs = await SharedPreferences.getInstance();

    // Aktuelle Queue laden
    final queue = await getQueue();

    final lastEvent = queue.isNotEmpty ? queue.last : null;
    if (lastEvent != null) {
      final timeDiff = event.timestamp.difference(lastEvent.timestamp).inSeconds.abs();

      // Duplikate vermeiden: Gleiches Event innerhalb von 30 Sekunden
      if (lastEvent.event == event.event &&
          lastEvent.zoneId == event.zoneId &&
          timeDiff < 30) {
        return; // Duplikat ignorieren
      }

      // Bounce-Protection: EXIT→ENTER oder ENTER→EXIT innerhalb von 5 Minuten ignorieren
      // Verhindert zerstückelte Einträge bei GPS-Fluktuation an der Zonengrenze
      if (lastEvent.zoneId == event.zoneId &&
          lastEvent.event != event.event &&
          timeDiff < 300) { // 5 Minuten
        return; // Bounce ignorieren
      }
    }

    // Event hinzufügen
    queue.add(event);

    // Speichern
    final jsonList = queue.map((e) => e.toJson()).toList();
    await prefs.setString(_queueKey, jsonEncode(jsonList));

    // Letztes Event speichern für schnellen Zugriff
    await prefs.setString(_lastEventKey, jsonEncode(event.toJson()));
  }

  /// Holt alle Events aus der Queue
  static Future<List<GeofenceEventData>> getQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_queueKey);

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((json) => GeofenceEventData.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Bei Fehler Queue leeren
      await prefs.remove(_queueKey);
      return [];
    }
  }

  /// Holt nur unverarbeitete Events
  static Future<List<GeofenceEventData>> getUnprocessedEvents() async {
    final queue = await getQueue();
    return queue.where((e) => !e.processed).toList();
  }

  /// Markiert Events als verarbeitet
  static Future<void> markAsProcessed(List<GeofenceEventData> events) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = await getQueue();

    for (final event in events) {
      final index = queue.indexWhere((e) =>
          e.timestamp == event.timestamp &&
          e.event == event.event &&
          e.zoneId == event.zoneId);
      if (index != -1) {
        queue[index] = queue[index].copyWith(processed: true);
      }
    }

    final jsonList = queue.map((e) => e.toJson()).toList();
    await prefs.setString(_queueKey, jsonEncode(jsonList));
  }

  /// Entfernt alte, verarbeitete Events (älter als 7 Tage)
  static Future<void> cleanup() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = await getQueue();
    final cutoff = DateTime.now().subtract(const Duration(days: 7));

    final filtered = queue.where((e) =>
        !e.processed || e.timestamp.isAfter(cutoff)).toList();

    final jsonList = filtered.map((e) => e.toJson()).toList();
    await prefs.setString(_queueKey, jsonEncode(jsonList));
  }

  /// Löscht die gesamte Queue
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey);
    await prefs.remove(_lastEventKey);
  }

  /// Holt das letzte Event (für Status-Anzeige)
  static Future<GeofenceEventData?> getLastEvent() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_lastEventKey);

    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }

    try {
      return GeofenceEventData.fromJson(jsonDecode(jsonString));
    } catch (e) {
      return null;
    }
  }

  /// Prüft ob aktuell "im Büro" (letztes Event war ENTER)
  static Future<bool> isCurrentlyInZone() async {
    final lastEvent = await getLastEvent();
    return lastEvent?.event == GeofenceEvent.enter;
  }
}
