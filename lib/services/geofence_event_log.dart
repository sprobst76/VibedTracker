import 'dart:convert';
import 'dart:developer';
import 'package:shared_preferences/shared_preferences.dart';
import 'geofence_event_queue.dart';

/// Ergebnis der Verarbeitung eines Geofence-Events durch den SyncService
enum GeofenceEventOutcome {
  /// Neue Arbeitszeit wurde gestartet
  started,

  /// Laufende Arbeitszeit wurde gestoppt
  stopped,

  /// Event wurde ignoriert (z.B. kein laufender Eintrag, EXIT vor START)
  ignored,

  /// EXIT-Event wurde ignoriert weil Session zu kurz war (< 25 min)
  shortSession,

  /// GPS-Drift: Session wurde nach kurzem Exit wieder fortgesetzt (Merge)
  merged,
}

/// Ein einzelner Log-Eintrag
class GeofenceEventLogEntry {
  final DateTime timestamp;
  final GeofenceEvent event;
  final String zoneId;
  final GeofenceEventOutcome outcome;

  /// Nur bei [GeofenceEventOutcome.merged]: Länge der Lücke in Minuten
  final int? gapMinutes;

  GeofenceEventLogEntry({
    required this.timestamp,
    required this.event,
    required this.zoneId,
    required this.outcome,
    this.gapMinutes,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'event': event.name,
        'zoneId': zoneId,
        'outcome': outcome.name,
        if (gapMinutes != null) 'gapMinutes': gapMinutes,
      };

  factory GeofenceEventLogEntry.fromJson(Map<String, dynamic> json) {
    return GeofenceEventLogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      event: GeofenceEvent.values.firstWhere(
        (e) => e.name == json['event'],
      ),
      zoneId: json['zoneId'] as String? ?? '',
      outcome: GeofenceEventOutcome.values.firstWhere(
        (e) => e.name == json['outcome'],
      ),
      gapMinutes: json['gapMinutes'] as int?,
    );
  }
}

/// Persistenter Log der zuletzt verarbeiteten Geofence-Events (max. [maxEntries]).
///
/// Wird in SharedPreferences als JSON-Array gespeichert. Neueste Einträge
/// stehen vorne. Ältere Einträge werden automatisch rotiert.
class GeofenceEventLog {
  static const _logKey = 'geofence_event_log';
  static const maxEntries = 50;

  /// Fügt einen Eintrag an den Anfang des Logs ein.
  /// Überschreitet der Log [maxEntries], werden die ältesten Einträge entfernt.
  static Future<void> append(GeofenceEventLogEntry entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = _decode(prefs.getString(_logKey));
      existing.insert(0, entry);
      if (existing.length > maxEntries) {
        existing.removeRange(maxEntries, existing.length);
      }
      await prefs.setString(_logKey, _encode(existing));
    } catch (e) {
      log('GeofenceEventLog.append failed: $e', name: 'GeofenceEventLog');
    }
  }

  /// Gibt alle Log-Einträge zurück (neueste zuerst).
  static Future<List<GeofenceEventLogEntry>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _decode(prefs.getString(_logKey));
    } catch (e) {
      log('GeofenceEventLog.getAll failed: $e', name: 'GeofenceEventLog');
      return [];
    }
  }

  /// Löscht alle Log-Einträge.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_logKey);
  }

  // ── Interne Hilfsmethoden ──────────────────────────────────────────────────

  static List<GeofenceEventLogEntry> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) =>
              GeofenceEventLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String _encode(List<GeofenceEventLogEntry> entries) {
    return jsonEncode(entries.map((e) => e.toJson()).toList());
  }
}
