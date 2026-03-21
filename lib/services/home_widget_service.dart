import 'dart:developer';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/work_entry.dart';

/// Aktualisiert das Android-Homescreen-Widget mit dem aktuellen Arbeitsstatus.
///
/// Schreibt Status-Daten in SharedPreferences (Prefix "flutter." → direkt
/// von der Kotlin AppWidgetProvider lesbar) und triggert dann via
/// MethodChannel eine native Widget-Aktualisierung.
class HomeWidgetService {
  static const _channel = MethodChannel('com.vibedtracker.app/widget');

  /// Aktualisiert das Widget basierend auf dem aktuellen WorkEntry.
  static Future<void> updateFromEntry(WorkEntry? runningEntry) async {
    final isRunning = runningEntry != null && runningEntry.stop == null;
    String status;
    String duration = '';

    if (isRunning) {
      final pauseDuration = _calculatePauseDuration(runningEntry);
      final netDuration = DateTime.now().difference(runningEntry.start) - pauseDuration;
      final inPause = runningEntry.pauses.isNotEmpty &&
          runningEntry.pauses.last.end == null;

      if (inPause) {
        status = 'Pause';
        duration = 'Gearbeitet: ${_fmtDuration(netDuration)}';
      } else {
        status = 'Seit ${_fmtTime(runningEntry.start)}';
        duration = _fmtDuration(netDuration);
      }
    } else {
      status = 'Inaktiv';
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_status', status);
      await prefs.setString('widget_duration', duration);
      await prefs.setBool('widget_running', isRunning);
      await _channel.invokeMethod('updateWidget');
    } catch (e) {
      // Widget ist möglicherweise nicht platziert — kein Fehler
      log('HomeWidgetService: update skipped ($e)', name: 'HomeWidgetService');
    }
  }

  static Duration _calculatePauseDuration(WorkEntry entry) {
    var total = Duration.zero;
    for (final pause in entry.pauses) {
      final end = pause.end ?? DateTime.now();
      total += end.difference(pause.start);
    }
    return total;
  }

  static String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}min';
    return '${m}min';
  }
}
