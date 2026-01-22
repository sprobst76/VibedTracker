import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Service to handle battery optimization settings for reliable background geofencing.
///
/// When Android's battery optimization is enabled for an app, the system may:
/// - Kill background services during memory pressure
/// - Delay or skip scheduled work
/// - Throttle location updates
///
/// This service helps the user disable battery optimization for VibedTracker
/// to ensure reliable geofence detection.
class BatteryOptimizationService {
  static const platform = MethodChannel('com.vibedtracker.app/battery');

  /// Checks if battery optimization is currently disabled for the app.
  /// Returns true if the app is whitelisted (optimization disabled).
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;

    try {
      final result = await platform.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Error checking battery optimization: ${e.message}');
      return false;
    } on MissingPluginException {
      debugPrint('Battery optimization plugin not available');
      return true; // Assume OK if plugin not available
    }
  }

  /// Opens the system settings to disable battery optimization for this app.
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;

    try {
      final result = await platform.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Error requesting battery optimization exemption: ${e.message}');
      return false;
    } on MissingPluginException {
      debugPrint('Battery optimization plugin not available');
      return false;
    }
  }

  /// Shows a dialog explaining why battery optimization should be disabled
  /// and offers to open the settings.
  static Future<void> showOptimizationDialog(BuildContext context) async {
    final isIgnoring = await isIgnoringBatteryOptimizations();

    if (isIgnoring) {
      debugPrint('Battery optimization already disabled');
      return;
    }

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Akkuoptimierung deaktivieren'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Für zuverlässige automatische Zeiterfassung muss die '
              'Akkuoptimierung für VibedTracker deaktiviert werden.',
            ),
            SizedBox(height: 12),
            Text(
              'Ohne diese Einstellung kann Android den Geofence-Service '
              'beenden und die Arbeitszeit wird nicht korrekt erfasst.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Später'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await requestIgnoreBatteryOptimizations();
            },
            child: const Text('Einstellungen öffnen'),
          ),
        ],
      ),
    );
  }
}
